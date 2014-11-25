class OffsiteBackup
  include Helpers

  def initialize(local_dir, description)
    @backend = offsite_backend_class().new(local_dir, description)
  end

  def push_offsite!
    @backend.push!
  rescue ProcessingError => e
    STDERR.puts "ERROR: #{e.message}"
  ensure
    puts  unless $options.quiet
  end

  def remove_old_backups!
    @backend.remove_old!
  rescue ProcessingError => e
    STDERR.puts "ERROR: #{e.message}"
  ensure
    puts  unless $options.quiet
  end

  private

  def offsite_backend_class
    case CONFIG['offsite']['backend']
    when 'test'
      OffsiteBackends::TestBackend
    when 'glacier'
      OffsiteBackends::GlacierBackend
    when 's3'
      OffsiteBackends::S3Backend
    else
      fail "Unknown offsite backend: #{backend}"
    end
  end
end
