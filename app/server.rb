require "socket"
require_relative "resp_decoder"
require "date"

class Command
  attr_reader :action
  attr_reader :args
  def initialize(action, args)
    @action = action
    @args = args
  end
end

# create a class to store key value pairs
# the class should have a expiry variable
# to set the expiry time for the key
# if the key is not accessed for the expiry time
# the key should be deleted
class KeyValue
  def initialize
    @store = {}
  end

  def add(key, value, expiry = 0)
    if expiry != 0
      expiry_time = millisecond_now + expiry.to_i
      @store[key] = [value, expiry_time]
      "OK"
    else
      @store[key] = [value]
      "OK"
    end
  end

  def get_key_value(key)
    if @store[key].length > 1 && @store[key] && @store[key][1] < millisecond_now
      @store[key][0]
    elsif @store[key].length == 1
      @store[key][0]
    else
      "-1"
    end
  end

  def millisecond_now
    DateTime.now.strftime('%Q').to_i
  end

end


class Client
  attr_reader :socket
  def initialize(socket)
    @socket = socket
    @buffer = ""
  end
  def consume_command!
    array = RESPDecoder.decode(@buffer)
    @buffer = ""
    Command.new(array[0], array[1..-1])
  rescue IncompleteRESP
    nil
  end
  def read_available
    @buffer += @socket.readpartial(1024)
  end
  def write(msg)
    @socket.write(msg)
  end
end

class YourRedisServer
  def initialize(port)
    @server = TCPServer.new(port)
    @sockets_to_clients = {}
    @storage = KeyValue.new
  end

  def listen
    loop do
      fds_to_watch = [@server, *@sockets_to_clients.keys]
      ready_to_read, _, _ = IO.select(fds_to_watch)
      ready_to_read.each do |fd|
        case fd
        when @server
          client_socket = @server.accept
          @sockets_to_clients[client_socket] = Client.new(client_socket)
        else
          client = @sockets_to_clients[fd]
          handle_client(client)
        end
      end
    end
  end

  def handle_client(client)
    client.read_available
    loop do
      command = client.consume_command!
      break unless command
      handle_command(client, command)
    end
    rescue Errno::ECONNRESET, EOFError
      @sockets_to_clients.delete(client.socket)
  end

  def handle_command(client, command)
    if command.action.downcase == "ping"
      client.write("+PONG\r\n")
    elsif command.action.downcase == "echo"
      client.write("+#{command.args[0]}\r\n")
    elsif command.action.downcase == "set"
      if command.args[2] && command.args[2].downcase == "px"
        operation = @storage.add(command.args[0], command.args[1], command.args[3])
        client.write("+#{operation}\r\n")
      else
        operation = @storage.add(command.args[0], command.args[1], 0)
        client.write("+#{operation}\r\n")
      end
    elsif command.action.downcase == "get"
      value = @storage.get_key_value(command.args[0])
      if value == "-1"
        puts "value #{value}"
        client.write("$#{value}\r\n")
      else
        client.write("$#{value.size}\r\n#{value}\r\n")
      end
    else
      raise RuntimeError.new("Unhandled command: #{command.action}")
    end
  end
end

YourRedisServer.new(6379).listen
