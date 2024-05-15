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
    @port = port
    @master_host = master_host
    @master_port = master_port
    @master_replid = "8371b4fb1155b71f4a04d3e1bc3e18c4a990aeeb"
    @master_repl_offset = 0
    @replica_connections = []
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
      response = "*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$#{@port.to_s.length}\r\n#{@port}\r\n"
      connection.puts(response)
      response = "*3\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n"
      connection.puts(response)
      repl_resp = connection.gets.chomp
      if repl_resp == "+OK"
        psync_command = "*3\r\n$5\r\nPSYNC\r\n$1\r\n?\r\n$2\r\n-1\r\n"
        connection.puts(psync_command)
        connection.gets
        response = ""
        while line = connection.gets
          response += line
          break if line.start_with?("+FULLRESYNC")
        end
        puts "Response from master: #{response}"
        if response.start_with?("+FULLRESYNC")
          puts "Received FULLRESYNC from master."
          read_rdb(connection)
        else
          puts "Unexpected response received from master server: #{response}. Aborting replication configuration."
        end
      end
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
      is_master = client.socket == @master_host
      if @role == "master" && command.action.downcase == "psync"
        @replica_connections << client
      end
      handle_command(client, command, is_master)
    end
    rescue Errno::ECONNRESET, EOFError
      @sockets_to_clients.delete(client.socket)
      @replica_connections.delete(client)
  end

  def handle_command(client, command, from_master = false)
    if command.action.downcase == "ping"
      client.write("+PONG\r\n") unless from_master
    elsif command.action.downcase == "echo"
      client.write("+#{command.args[0]}\r\n") unless from_master
    elsif command.action.downcase == "set"
      operation = @storage.add(command.args[0], command.args[1], command.args[2]&.downcase == "px" ? command.args[3] : nil)
      client.write("+#{operation}\r\n") unless from_master
      propagate_command(command)
    elsif command.action.downcase == "get"
      value = @storage.get_key_value(command.args[0])
      client.write("$#{value == "-1" ? value : "#{value.size}\r\n#{value}"}\r\n") unless from_master
    elsif command.action.downcase == "info"
      info = @info.replication_info
      client.write("$#{info.size}\r\n#{info}\r\n") unless from_master
    elsif command.action.downcase == "replconf"
      # receive handshake as master
      client.write("+OK\r\n") unless from_master
    elsif command.action.downcase == "psync"
      puts "Received PSYNC command. #{command.args}"
      if command.args[0] == "?" && command.args[1] == "-1"
        puts "Received PSYNC command with ? and -1 arguments."
        client.write("+FULLRESYNC #{@master_replid} #{@master_repl_offset}\r\n") unless from_master
        send_empty_rdb(client)
      else
        raise RuntimeError.new("Unhandled PSYNC command: #{command.args}")
      end
    else
      raise RuntimeError.new("Unhandled command: #{command.action}")
    end
  end

  def send_empty_rdb(client)
    # An empty RDB file in hex representation
    empty_rdb_hex = "524544495330303131fa0972656469732d76657205372e322e30fa0a72656469732d62697473c040fa056374696d65c26d08bc65fa08757365642d6d656dc2b0c41000fa08616f662d62617365c000fff06e3bfec0ff5aa2"
    # Convert the hex representation to binary
    empty_rdb = [empty_rdb_hex].pack("H*")
    # Send the empty RDB file as a RESP Bulk String
    client.write("$#{empty_rdb.bytesize}\r\n#{empty_rdb}")
  end

  def read_rdb(connection)
    # Read the RDB file from the socket
    puts "Reading RDB file..."
    while data = connection.read(1024)
      # Process the data...
      puts "RDB data: #{data}"
    end
    puts "Finished reading RDB file."
  end

  def propagate_command(command)
    # Check if the server is a master and has connected replicas
    if @role == "master" && @replica_connections.any?
      # Convert the command to a RESP Array
      resp_command = "*#{command.args.size + 1}\r\n$#{command.action.size}\r\n#{command.action}\r\n" + command.args.map { |arg| "$#{arg.size}\r\n#{arg}\r\n" }.join
      # Send the command to all connected replicas
      @replica_connections.each do |connection|
        connection.write(resp_command)
      end
    end
  end

  def handle_propagated_commands(connection)
    # Handle the propagated commands
    puts "Handling propagated commands..."
    while command_string = connection.gets
      # Decode the command string into a Command object
      command_array = RESPDecoder.decode(command_string.chomp)
      command = Command.new(command_array[0], command_array[1..-1])

      # Handle the command using the handle_command method
      handle_command(Client.new(connection), command, true)
    end
    puts "Finished handling propagated commands."
  end
end

port = ARGV[1] || ENV['SERVER_PORT']
master_host = nil
master_port = nil
args = ARGV.dup
replicaof_index = args.index("--replicaof")
if replicaof_index
  master_host_port = args[replicaof_index + 1].split(" ")
  master_host, master_port = master_host_port[0], master_host_port[1]
  role = "slave"
  # Remove the processed arguments
  args.slice!(replicaof_index, 2)
else
  role = "master"
end
puts "Master host: #{master_host}"
YourRedisServer.new(port, role, master_host, master_port).listen
