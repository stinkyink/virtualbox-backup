class VirtualMachineBackup
  include Helpers

  attr_accessor :target_dir, :time

  def initialize(vm)
    @vm = vm
    @time = Time.now
    @target_dir = File.join(OUT_DIR, @time.strftime('%Y-%m-%d'), @vm.name)
    @error = false
  end

  def do_backup!
    hdds = @vm.hard_disks_and_ancestors
    backup_config(exclude: hdds.map(&:path))
    backup_hard_disks(hdds)
  rescue ProcessingError => e
    name = @vm.to_s  rescue @vm.uuid
    STDERR.puts "ERROR: #{name}: #{e.message}"
    @error = true
  ensure
    puts  if VERBOSE
  end

  def virtual_machine
    @vm
  end

  def error?
    @error
  end

  private

  def backup_config(options = {})
    exclude_files = options.fetch(:exclude, [])
    backup_dir = File.dirname(@vm.config_file)
    out_file = File.join(@target_dir, 'config.tar.gz')
    FileUtils.mkdir_p(File.dirname(out_file))
    say "== Backing up #{@vm.name} Config"
    unless exclude_files.empty?
      exclude = exclude_files.select {|file|
        file.start_with?(backup_dir)
      }.map {|file|
        %(--exclude "#{file[(backup_dir.length + 1)..-1]}")
      }.join(' ')
    end
    v = VERBOSE ? 'v' : ''
    cmd = %(tar c#{v}z -C "#{File.dirname(backup_dir)}" #{exclude} ) +
          %("#{File.basename(backup_dir)}" > "#{out_file}")
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail 'Failed to back up config'
    end
  end

  def backup_hard_disks(hdds)
    data_by_mountpoint = Hash.new
    hdds.each do |hdd|
      info = path_info(hdd.path)
      data = (data_by_mountpoint[info[:mountpoint]] ||= Hash.new)
      data[:lvm_lv] = info[:lvm_lv]
      (data[:hdds] ||= Array.new) << hdd
    end
    # Create snapshots of the underlying LV for each mountpoint
    whilst_paused do
      data_by_mountpoint.each_pair do |mountpoint, data|
        data[:snapshot_lv] = create_snapshot_of(data[:lvm_lv])
      end
    end
    # Backup the hard disks from each mountpoint using its LVM snapshot
    data_by_mountpoint.each_pair do |mountpoint, data|
      with_mounted_lv(data[:snapshot_lv]) do |snapshot_mountpoint|
        data[:hdds].each do |hdd|
          relative_hdd_path = hdd.path[(mountpoint.length + 1)..-1]
          snapshot_hdd_path = File.join(snapshot_mountpoint, relative_hdd_path)
          backup_hard_disk_file(snapshot_hdd_path)
        end
      end
    end
  ensure
    data_by_mountpoint.values.map {|x| x[:snapshot_lv] }.
      reject(&:nil?).reject(&:empty?).each do |snapshot_lv|
        remove_snapshot(snapshot_lv)
      end
  end

  def backup_hard_disk_file(hdd_path)
    out_file = File.join(@target_dir, 'HDDs', File.basename(hdd_path) + '.gz')
    FileUtils.mkdir_p(File.dirname(out_file))
    source_cmd = VERBOSE ? %(pv "#{hdd_path}") : %(cat "#{hdd_path}")
    cmd = %(#{source_cmd} | gzip > "#{out_file}")
    say "== Backing up #{@vm.name} HDD #{File.basename(hdd_path)}"
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail "Failed to back up HDD: #{hdd_path}"
    end
  end

  def with_mounted_lv(lvm_lv)
    Dir.mktmpdir {|dir|
      say "== Mounting #{lvm_lv} on #{dir}"
      `#{MOUNT} /dev/#{lvm_lv} #{dir} > /dev/null`
      if $?.exitstatus != 0
        fail "Failed to mount snapshot #{lvm_lv} on #{dir}"
      end
      begin
        yield dir
      ensure
        say "== Unmounting #{lvm_lv} from #{dir}"
        `#{UMOUNT} /dev/#{lvm_lv} > /dev/null`
        if $?.exitstatus != 0
          fail "Failed to unmount snapshot #{lvm_lv} from #{dir}"
        end
      end
    }
  end

  def create_snapshot_of(lvm_lv)
    say "== Creating snapshot of #{lvm_lv}"
    snapshot_lv = lvm_lv + '-backup'
    cmd = "#{LVM} lvcreate -L10G --snapshot " +
          "--name #{File.basename(snapshot_lv)} #{lvm_lv} > /dev/null"
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail "Failed to create snapshot of #{lvm_lv}"
    end
    snapshot_lv
  end

  def remove_snapshot(snapshot_lv)
    say "== Removing #{snapshot_lv}"
    cmd = "#{LVM} lvremove -f #{snapshot_lv} > /dev/null"
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail "Failed to remove snapshot #{snapshot_lv}"
    end
  end

  def path_info(path)
    fields = `df -P "#{path}"`.split("\n")[1].split
    device = fields[0]
    lvm_lv = File.basename(device).sub(/(?<!-)-(?!-)/, '/').gsub('--', '-')
    mountpoint = fields.reverse.find {|x| x.start_with?('/') }
    if $?.exitstatus != 0 || [device, lvm_lv, mountpoint].include?(nil)
      fail "Unable to determine mountpoint for #{hdd.path}"
    end
    {
      device: device,
      lvm_lv: lvm_lv,
      mountpoint: mountpoint
    }
  end

  def whilst_paused(&block)
    pause_for_snapshot = CONFIG['virtual_machines']['pause-for-snapshot']
    if pause_for_snapshot && @vm.state == 'running'
      say "== Pausing: #{@vm}"
      @vm.save!
      begin
        yield
      ensure
        say "== Resuming: #{@vm}"
        @vm.start!
      end
    else
      yield
    end
  end
end
