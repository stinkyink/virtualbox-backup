module OffsiteBackends
class Backend
  include Helpers

  def initialize(local_dir, description)
    @local_dir = local_dir
    @description = description
  end

  def remove_old!
    STDERR.puts 'WARNING: This offsite backend does not implement the ' +
                'removal of old backups.'
  end

  protected

  def with_offsite_data_io(&block)
    tar_cmd = %(tar c -C "#{File.dirname(@local_dir)}" ) +
              %("#{File.basename(@local_dir)}")
    unless $options.quiet
      pv_cmd = "pv -s #{directory_size(@local_dir)}"
    end
    IO.pipe do |passphrase_out, passphrase_in|
      passphrase_in.puts(CONFIG['offsite']['encryption-key'])
      passphrase_in.close
      gpg_cmd =
        'gpg --batch --symmetric --compress-algo none --cipher-algo AES256 ' +
        "--passphrase-file /proc/#{Process.pid}/fd/#{passphrase_out.to_i}"
      cmd = [tar_cmd, pv_cmd, gpg_cmd].compact.join(' | ')
      say "# #{cmd}"
      IO.pipe do |data_out, data_in|
        pid = Process.spawn(cmd, out: data_in)
        data_in.close
        yield(data_out)
        Process.wait(pid)
        if $?.exitstatus != 0
          fail 'Failed to read backup data to push offsite'
        end
      end
    end
  end

  def directory_size(path)
    out = `du -sb "#{path}"`
    if $?.exitstatus != 0
      fail "Unable to determine size of directory: #{path}"
    end
    out.split.first
  end

  def expiry_date
    days = CONFIG['offsite']['expiry-days']
    Time.now - (60 * 60 * 24 * days).round
  end
end
end
