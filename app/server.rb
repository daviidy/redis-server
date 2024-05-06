require "socket"
require_relative "resp_decoder"
require "date"
require 'dotenv'
Dotenv.load

class Command
  attr_reader :action
  attr_reader :args
  def initialize(action, args)
    @action = action
    @args = args
  end
end

class Info
  def initialize(server)
    @server = server
  end

  def replication_info
    "# Replication\r\nrole:#{@server.role}\r\nmaster_replid:#{@server.master_replid}\r\nmaster_repl_offset:#{@server.master_repl_offset}\r\n"
  end
end


class KeyValue
  def initialize
    @store = {}
  end

  def add(key, value, expiry)
    expiry_time = expiry ? millisecond_now + expiry.to_i : expiry
    @store[key] = [value, expiry_time].compact
    "OK"
  end

  def get_key_value(key)
    if @store[key].length > 1 && @store[key][1] > millisecond_now
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
  attr_reader :role, :master_replid, :master_repl_offset, :port
  def initialize(port, role = "master", master_host = nil, master_port = nil)
    @server = TCPServer.new(port)
    @sockets_to_clients = {}
    @storage = KeyValue.new
    @role = role
    @master_host = master_host
    @master_port = master_port
    @master_replid = "8371b4fb1155b71f4a04d3e1bc3e18c4a990aeeb"
    @master_repl_offset = 0
    @info = Info.new(self)
    if master_port && master_host
      do_handshake
    end
  end

  def do_handshake
    # send PING
    connection = TCPSocket.new(@master_host, @master_port)
    connection.puts("*1\r\n$4\r\nPING\r\n")
    pong_resp = connection.gets.chomp
    if pong_resp == "+PONG"
      response = "*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$#{@port.to_s.size}\r\n#{@port}\r\n"
      master.puts(response)
      response = "*3\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n"
      master.puts(response)
    else
      puts "Unexpected response received from master server: #{pong_resp}. Aborting replication configuration."
    end
  rescue Errno::ECONNREFUSED => e
    puts "Master not available: #{e.message}"
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
      operation = @storage.add(command.args[0], command.args[1], command.args[2]&.downcase == "px" ? command.args[3] : nil)
      client.write("+#{operation}\r\n")
    elsif command.action.downcase == "get"
      value = @storage.get_key_value(command.args[0])
      client.write("$#{value == "-1" ? value : "#{value.size}\r\n#{value}"}\r\n")
    elsif command.action.downcase == "info"
      info = @info.replication_info
      client.write("$#{info.size}\r\n#{info}\r\n")
    elsif command.action.downcase == "repliconf"
      client.write("+OK\r\n")
    else
      raise RuntimeError.new("Unhandled command: #{command.action}")
    end
  end
end

port = ARGV[1] || ENV['SERVER_PORT']
role = ARGV[2] == "--replicaof" ? "slave" : "master"
master_host = ARGV[2] == "--replicaof" ? ARGV[3] : nil
master_port = ARGV[2] == "--replicaof" ? ARGV[4] : nil
YourRedisServer.new(port, role, master_host, master_port).listen
