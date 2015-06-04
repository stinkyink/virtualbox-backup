module OffsiteBackends
class S3Backend < Backend
  def push!
    say "== Pushing #{@local_dir} to Amazon S3"
    with_offsite_data_io do |data_in|
      push_io_into_s3_file(data_in)
    end
  end

  def remove_old!
    old_files = s3_bucket().files.select {|file|
      matches = file.key[(file.key.index(' ') + 1)..-1]
      matches[1] == @name && file.last_modified < expiry_date()
    }
    return  if old_files.empty?
    say "== Removing backups older than #{expiry_date()}"
    old_files.to_a.each do |file|
      say "-> #{file.key}"
      file.destroy
    end
  end

  private

  def push_io_into_s3_file(io_in)
    # patch io so that #pos= is a null-op, as Excon attempts to call it
    def io_in.rewind
    end
    s3_bucket().files.
      create(key: @description,
             body: io_in,
             multipart_chunk_size: CONFIG['aws']['upload-chunk-size'])
  end

  def s3_bucket
    s3 = Fog::Storage::AWS.new({
      aws_access_key_id: CONFIG['aws']['access-key'],
      aws_secret_access_key: CONFIG['aws']['secret-key'],
      region: CONFIG['aws']['region']
    })
    s3.directories.get(CONFIG['aws']['s3']['bucket'])
  end
end
end
