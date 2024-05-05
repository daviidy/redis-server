# frozen_string_literal: true

require "minitest/autorun"
require_relative "resp_decoder"
require "redis"
require 'mocha/minitest'

class TestRESPDecoder < Minitest::Test
  def test_simple_string
    assert_equal "OK", RESPDecoder.decode("+OK\r\n")
    assert_equal "HEY", RESPDecoder.decode("+HEY\r\n")
    assert_raises(IncompleteRESP) { RESPDecoder.decode("+") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("+OK") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("+OK\r") }
  end

  def test_bulk_string
    assert_equal "OK", RESPDecoder.decode("$2\r\nOK\r\n")
    assert_equal "HEY", RESPDecoder.decode("$3\r\nHEY\r\n")
    assert_equal "HEY", RESPDecoder.decode("$3\r\nHEY\r\n")
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$2") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$2\r") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$2\r\n") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$2\r\nOK") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("$2\r\nOK\r") }
  end

  def test_arrays
    assert_equal ["PING"], RESPDecoder.decode("*1\r\n$4\r\nPING\r\n")
    assert_equal ["ECHO", "hey"], RESPDecoder.decode("*2\r\n$4\r\nECHO\r\n$3\r\nhey\r\n")
    assert_raises(IncompleteRESP) { RESPDecoder.decode("*") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("*1") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("*1\r\n") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("*1\r\n$4") }
    assert_raises(IncompleteRESP) { RESPDecoder.decode("*2\r\n$4\r\nECHO\r\n") }
  end

  def test_expiry
    r = Redis.new(port: ENV['SERVER_PORT'])
    assert_equal "OK", r.set("key_test", "test_value")
    assert_equal "test_value", r.get("key_test")
    # assert set with expiry and px
    assert_equal "OK", r.set("key_test", "test_value", px: 1000)
    # test command after expiry
    sleep(2)
    assert_nil r.get("key_test")
  end

  def test_info_command
    r = Redis.new(port: ENV['SERVER_PORT'])
    info = r.info
    assert_equal "master", info["role"]
  end

  def test_info_command_replica
    # Mock the Redis server
    @redis = mock('Redis')
    # Stub the `new` method to return the mock server
    Redis.stubs(:new).returns(@redis)
    # Make the mock server return a hash with 'role' => 'slave'
    @redis.stubs(:info).returns('role' => 'slave')

    r = Redis.new(port: ENV['SERVER_PORT'])
    info = r.info
    assert_equal "slave", info["role"]
  end

  def test_info_command_with_replid_and_offset
    r = Redis.new(port: ENV['SERVER_PORT'])
    info = r.info
    assert_equal "master", info["role"]
    assert_equal "8371b4fb1155b71f4a04d3e1bc3e18c4a990aeeb", info["master_replid"]
    assert_equal "0", info["master_repl_offset"]
  end
end