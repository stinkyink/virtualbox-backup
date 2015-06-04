class VirtualMachine
  include Helpers

  attr_reader :name
  alias :to_s :name

  def self.find(arg)
    [*arg].map {|name|
      begin
        self.new(name)
      rescue ProcessingError => e
        STDERR.puts %(WARNING: Unable to find VM "#{name}": #{e.message})
        nil
      end
    }.compact
  end

  def initialize(name)
    @name = name
  rescue ProcessingError => e
    fail "Unable to initialize: #{e.message}"
  end

  def disks
    xml_config.xpath('//disk').map {|disk|
      source = disk.at_xpath('source').attributes['dev'].value
      valid_disk?(disk, source) ? source : nil
    }.compact
  end

  def xml_config
    cmd = "#{SUDO} virsh dumpxml #{@name}"
    xml = Nokogiri::XML(`#{cmd}`)
    if $?.exitstatus != 0
      fail "Unable to retrieve config."
    end
    xml
  end

  private

  def valid_disk?(disk, source)
    if disk.attributes['type'].value != 'block'
      STDERR.puts "WARNING: Unable to back up disk with source #{source}: " +
                  "only block devices are supported."
      return false
    end
    true
  end
end
