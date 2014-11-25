module OffsiteBackends
class GlacierBackend < Backend
  def push!
    say "== Pushing #{@local_dir} to Amazon Glacier"
    with_offsite_data_io do |data_in|
      push_io_into_glacier_archive(data_in)
    end
  end

  private

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
    CSV.open(CONFIG['aws']['glacier']['archive-list-file'], 'a') do |log_out|
      log_out << [@description, archive.id]
    end
  end
end
end
