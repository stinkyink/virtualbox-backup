module OffsiteBackends
class TestBackend < Backend
  def push!
    say "== Pushing #{@local_dir} to Test File"
    with_offsite_data_io do |data_in|
      push_io_into_test_file(data_in)
    end
  end

  private

  def push_io_into_test_file(io_in)
    io_out = File.open(File.join(SCRIPT_DIR, 'test.out'), 'w')
    while true do
      buffer = io_in.read(CONFIG['aws']['upload-chunk-size'])
      break  if buffer.nil?
      io_out.write(buffer)
    end
    io_out.close
  end
end
end
