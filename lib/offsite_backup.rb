class OffsiteBackup
  include Helpers

  def initialize(local_dir, description)
    @local_dir = local_dir
    @description = description
  end

  def push_offsite!
    backend = CONFIG['offsite-backend']
    case backend
    when 'test'
      push_to_test_file!
    when 'glacier'
      push_to_glacier!
    when 's3'
      push_to_s3!
    else
      fail "Unknown offsite backend: #{backend}"
    end
  rescue ProcessingError => e
    STDERR.puts "ERROR: #{@vm}: #{e.message}"
  ensure
    puts  unless $options.quiet
  end

  private

  def push_to_test_file!
    say "== Pushing #{@local_dir} to Test File"
    with_offsite_data_io do |data_in|
      push_io_into_test_file(data_in)
    end
  end

  def push_to_glacier!
    say "== Pushing #{@local_dir} to Amazon Glacier"
    with_offsite_data_io do |data_in|
      push_io_into_glacier_archive(data_in)
    end
  end

  def push_to_s3!
    say "== Pushing #{@local_dir} to Amazon S3"
    with_offsite_data_io do |data_in|
      push_io_into_s3_file(data_in)
    end
  end

  def with_offsite_data_io(&block)
    tar_cmd = %(tar c -C "#{File.dirname(@local_dir)}" ) +
              %("#{File.basename(@local_dir)}")
    unless $options.quiet
      pv_cmd = "pv -s #{directory_size(@local_dir)}"
    end
    IO.pipe do |passphrase_out, passphrase_in|
      passphrase_in.puts(CONFIG['encryption']['key'])
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

  def push_io_into_test_file(io_in)
    io_out = File.open(File.join(SCRIPT_DIR, 'test.out'), 'w')
    while true do
      buffer = io_in.read(CONFIG['aws']['upload-chunk-size'])
      break  if buffer.nil?
      io_out.write(buffer)
    end
    io_out.close
  end

  def push_io_into_glacier_archive(io_in)
    # patch io so that #rewind is a null-op, as Fog attempts to rewind it
    def io_in.rewind
    end
    glacier =
      Fog::AWS::Glacier.new(aws_access_key_id: CONFIG['aws']['access-key'],
                            aws_secret_access_key: CONFIG['aws']['secret-key'],
                            region: CONFIG['aws']['region'])
    vault = glacier.vaults.get(CONFIG['aws']['glacier']['vault'])
    archive =
      vault.archives.
        create(description: @description,
               body: io_in,
               multipart_chunk_size:
                 CONFIG['aws']['upload-chunk-size'])
    say "Glacier archive: #{@description}"
    say "Glacier archive ID: #{archive.id}"
    CSV.open(CONFIG['local']['archive-list-file'], 'a') do |log_out|
      log_out << [@description, archive.id]
    end
  end

  def push_io_into_s3_file(io_in)
    # patch io so that #pos= is a null-op, as Excon attempts to call it
    def io_in.rewind
    end
    s3 = Fog::Storage::AWS.new({
      aws_access_key_id: CONFIG['aws']['access-key'],
      aws_secret_access_key: CONFIG['aws']['secret-key'],
      region: CONFIG['aws']['region']
    })
    bucket = s3.directories.get(CONFIG['aws']['s3']['bucket'])
    bucket.files.
      create(key: @description,
             body: io_in,
             multipart_chunk_size: CONFIG['aws']['upload-chunk-size'])
  end

  def directory_size(path)
    out = `du -sb "#{path}"`
    if $?.exitstatus != 0
      fail "Unable to determine size of directory: #{path}"
    end
    out.split.first
  end
end
