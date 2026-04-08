require "test_helper"

class Daan::Core::MemoryTest < ActiveSupport::TestCase
  test "storage is a SwarmMemory::Core::Storage instance" do
    assert_instance_of SwarmMemory::Core::Storage, Daan::Core::Memory.storage
  end

  test "storage is memoized (same object on every call)" do
    first = Daan::Core::Memory.storage
    second = Daan::Core::Memory.storage
    assert_same first, second
  end
end
