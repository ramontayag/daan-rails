require "test_helper"

class Daan::MemoryTest < ActiveSupport::TestCase
  test "storage is a SwarmMemory::Core::Storage instance" do
    assert_instance_of SwarmMemory::Core::Storage, Daan::Memory.storage
  end

  test "storage is memoized (same object on every call)" do
    first = Daan::Memory.storage
    second = Daan::Memory.storage
    assert_same first, second
  end
end
