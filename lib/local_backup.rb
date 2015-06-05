class VirtualMachineBackup
  include Helpers

  def initialize(vm)
    @vm = vm
    @error = false
  end

  def do_backup!
    @time = Time.now
    backup_config
    backup_disks(@vm.disks)
  rescue ProcessingError => e
    name = @vm.to_s  rescue @vm.uuid
    STDERR.puts "ERROR: #{name}: #{e.message}"
    @error = true
  ensure
    puts  unless $options.quiet
  end

  def completed_backup_dirs
    Dir.glob(File.join(OUT_DIR, '**', @vm.name)).
      reject {|x|
        backup_root = File.basename(File.dirname(x))
        backup_root.start_with?('0-new')
      }.sort
  end

  def virtual_machine
    @vm
  end

  def time
    if @time.nil?
      date_dir = File.dirname(completed_backup_dirs.first)
      @time = DateTime.strptime(date_dir[-10..-1], '%Y-%m-%d')
    end
    @time
  end

  def error?
    @error
  end

  private

  def backup_config
    out_file = File.join(target_dir(), "#{@vm.name}.xml.gz")
    FileUtils.mkdir_p(File.dirname(out_file))
    say "== Backing up #{@vm.name} Config"
    cmd = %(#{SUDO} virsh dumpxml "#{@vm.name}" | gzip > "#{out_file}").lstrip
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail 'Failed to back up config'
    end
  end

  def backup_disks(disks)
    disks.each do |disk|
      lv = lv_from_device_path(disk)
      if lv.nil?
        STDERR.puts "WARNING: Ignoring disk #{disk} as path format is " +
                    "unexpected. Expected LVM block device, like /dev/vg/lg."
        next
      end
      snapshot_lv = create_snapshot_of(lv)
      begin
        out_path =
          File.join(target_dir(), 'disks', File.basename(lv) + '.gz')
        backup_block_device("/dev/#{snapshot_lv}", out_path)
      ensure
        remove_lv(snapshot_lv)
      end
    end
  end

  def backup_block_device(block_device, out_path)
    FileUtils.mkdir_p(File.dirname(out_path))
    cmd = %(#{SUDO} dd if=#{block_device} bs=1M 2> /dev/null).lstrip
    unless $options.quiet
      size = `#{SUDO} blockdev --getsize64 #{block_device}`.chomp
      cmd << %( | pv -s #{size} -B 1m)
    end
    cmd << %( | gzip > "#{out_path}")
    say "== Backing up #{@vm.name} disk at #{block_device} to #{out_path}"
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail "Failed to back up disk #{block_device}"
    end
  end

  def create_snapshot_of(lvm_lv)
    say "== Creating snapshot of #{lvm_lv}"
    snapshot_lv = lvm_lv + '-vm-backup'
    lvcreate_args =
      @vm.config['snapshot-lvcreate-args'] ||
        CONFIG['local']['default-snapshot-lvcreate-args']
    cmd = "#{SUDO} lvm lvcreate #{lvcreate_args} --snapshot ".lstrip +
          "--name #{File.basename(snapshot_lv)} #{lvm_lv} > /dev/null"
    say "# #{cmd}"
    pid = Process.spawn(cmd)
    Process.wait(pid)
    if $?.exitstatus != 0
      fail "Failed to create snapshot of #{lvm_lv}"
    end
    snapshot_lv
  end

  def remove_lv(lv)
    say "== Removing #{lv}"
    cmd = "#{SUDO} lvm lvremove -f #{lv} 2>&1 > /dev/null".lstrip
    say "# #{cmd}"
    output = ""
    6.times do
      output = `#{cmd}`
      break  if $?.exitstatus == 0
      sleep 5
    end
    if $?.exitstatus != 0
      STDERR.puts "WARNING: #{@vm}: Failed to remove logical volume #{lv}"
      STDERR.puts "Output was:"
      STDERR.print output.split("\n").map {|x| "  #{x}"}.join("\n")
    end
  end

  def target_dir
    date = @time.strftime("%Y-%m-%d")
    File.join(OUT_DIR, "0-new_#{date}", @vm.name)
  end

  def lv_from_device_path(path)
    matches = %r(^/dev((?:/[^/]+){2})$).match(path)
    return nil  if matches.nil?
    matches[1][1..-1]
  end
end
