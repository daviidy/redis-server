# frozen_string_literal: true
require 'stringio'

class IncompleteRESP < Exception; end

class RESPDecoder
  def self.decode(resp_str)
    resp_io = StringIO.new(resp_str)
    first_char = resp_io.read(1)
    if first_char == "+"
      self.decode_simple_string(resp_io)
    elsif first_char == "$"
      self.decode_bulk_string(resp_io)
    else
      raise RuntimeError.new("Unhandled first_char: #{first_char}")
    end
  rescue EOFError
    raise IncompleteRESP
  end

  def self.decode_simple_string(resp_io)
    read = resp_io.readline(sep = "\r\n")
    if read[-2..-1] != "\r\n"
      raise IncompleteRESP
    end

    read[0..-3]
  end
  def self.decode_bulk_string(resp_io)
    byte_count_with_clrf = resp_io.readline(sep = "\r\n")
    if byte_count_with_clrf[-2..-1] != "\r\n"
      raise IncompleteRESP
    end
    byte_count = byte_count_with_clrf.to_i
    str = resp_io.read(byte_count)
    # Exactly the advertised number of bytes must be present
    raise IncompleteRESP unless str && str.length == byte_count
    # Consume the ending CLRF
    raise IncompleteRESP unless resp_io.read(2) == "\r\n"
    str
  end
end