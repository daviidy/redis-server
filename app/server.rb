require "socket"
require_relative "resp_decoder"

class Command
  attr_reader :action
  attr_reader :args
  def initialize(action, args)
    @action = action
    @args = args
  end
end
class Client
  attr_reader :socket
  def initialize(socket)
    @socket = socket
    @buffer = ""
  end
  def consume_command!
    puts "Buffer: #{@buffer.inspect}"
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

    if command.action == "PING"
      p "here ping"
      client.write("+PONG\r\n")
    elsif command.action == "ECHO"
      client.write("+#{command.args[0]}\r\n")
    else
      raise RuntimeError.new("Unhandled command: #{command.action}")
    end
  end
end

YourRedisServer.new(6379).listen
