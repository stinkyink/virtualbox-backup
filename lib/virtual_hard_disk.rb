class VirtualHardDisk
  include Helpers

  attr_reader :uuid

  def initialize(uuid)
    @uuid = uuid
  end

  def parent
    parent_uuid = parent_uuids[@uuid]
    if parent_uuid.nil?
      fail("No parent UUID found for HDD #{@uuid}")
    end
    if parent_uuid == 'base'
      nil
    else
      self.class.new(parent_uuid)
    end
  end

  def ancestors
    list = [self.parent]
    until list.last.nil?
      list << list.last.parent
    end
    list.pop
    list
  end

  def is_dvd?
    dvd_uuids.include?(@uuid)
  end

  def path
    info['Location'] || fail("No location found for HDD #{@uuid}")
  end

  private

  def parent_uuids
    return @@parent_uuids  if defined?(@@parent_uuids)
    @@parent_uuids = Hash.new
    current_uuid = nil
    `#{VBOX_MANAGE} list hdds`.split("\n").each do |line|
      key, value = line.split(':').map(&:strip)
      current_uuid = value  if key == 'UUID'
      if key == 'Parent UUID'
        @@parent_uuids[current_uuid] = value
      end
    end
    if $?.exitstatus != 0
      fail 'Failed to get list of virtual hard disks'
    end
    @@parent_uuids
  end

  def dvd_uuids
    @@dvd_uuids ||=
      `#{VBOX_MANAGE} list dvds`.split("\n").each_with_object(Array.new) {|line, acc|
        key, value = line.split(':').map(&:strip)
        acc << value  if key == 'UUID'
      }
  end

  def info
    @info ||=
      `#{VBOX_MANAGE} showhdinfo #{@uuid}`.split("\n").
        each_with_object(Hash.new) do |line, acc|
          split = line.index(':')
          key = line[0..(split - 1)]
          value = line[(split + 1)..-1]
          key, value = [key, value].map(&:strip)
          acc[key] = value
        end
  end
end

