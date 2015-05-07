require 'json'
require 'session_helper'

module Sessions

  # get application root directory
  @root = Dir.pwd.to_s
  if !@root || @root.empty? || @root == '/'
    @root = Rails.root
  end

  # get working directories
  @path = "#{@root}/tmp/websocket"

  # create global vars for threads
  @@client_threads = {}

=begin

start new session

  Sessions.create( client_id, session_data, { :type => 'websocket' } )

returns

  true|false

=end

  def self.create( client_id, session, meta )
    path         = "#{@path}/#{client_id}"
    path_tmp     = "#{@path}/tmp/#{client_id}"
    session_file = "#{path_tmp}/session"

    # collect session data
    meta[:last_ping] = Time.new.to_i.to_s
    data = {
      user: session,
      meta: meta,
    }
    content = data.to_json

    # store session data in session file
    FileUtils.mkpath path_tmp
    File.open( session_file, 'wb' ) { |file|
      file.write content
    }

    # destory old session if needed
    if File.exist?( path )
      Sessions.destory(client_id)
    end

    # move to destination directory
    FileUtils.mv( path_tmp, path )

    # send update to browser
    if session && session['id']
      send(
        client_id,
        {
          event: 'ws:login',
          data: { success: true },
        }
      )
    end
  end

=begin

list of all session

  client_ids = Sessions.sessions

returns

  ['4711', '4712']

=end

  def self.sessions
    path = "#{@path}/"

    # just make sure that spool path exists
    if !File.exist?( path )
      FileUtils.mkpath path
    end

    data = []
    Dir.foreach( path ) do |entry|
      next if entry == '.'
      next if entry == '..'
      next if entry == 'tmp'
      next if entry == 'spool'
      data.push entry.to_s
    end
    data
  end

=begin

list of all session

  Sessions.session_exists?(client_id)

returns

  true|false

=end

  def self.session_exists?(client_id)
    client_ids = sessions
    client_ids.include? client_id.to_s
  end

=begin

list of all session with data

  client_ids_with_data = Sessions.list

returns

  {
    '4711' => {
      :user => {
        'id' => 123,
      },
      :meta => {
        :type      => 'websocket',
        :last_ping => time_of_last_ping,
      }
    },
    '4712' => {
      :user => {
        'id' => 124,
      },
      :meta => {
        :type      => 'ajax',
        :last_ping => time_of_last_ping,
      }
    },
  }

=end

  def self.list
    client_ids = sessions
    session_list = {}
    client_ids.each { |client_id|
      data = get(client_id)
      next if !data
      session_list[client_id] = data
    }
    session_list
  end

=begin

destroy session

  Sessions.destory(client_id)

returns

  true|false

=end

  def self.destory( client_id )
    path = "#{@path}/#{client_id}"
    FileUtils.rm_rf path
  end

=begin

destroy idle session

  list_of_client_ids = Sessions.destory_idle_sessions

returns

  ['4711', '4712']

=end

  def self.destory_idle_sessions(idle_time_in_sec = 240)
    list_of_closed_sessions = []
    clients                 = Sessions.list
    clients.each { |client_id, client|
      if !client[:meta] || !client[:meta][:last_ping] || ( client[:meta][:last_ping].to_i + idle_time_in_sec ) < Time.now.to_i
        list_of_closed_sessions.push client_id
        Sessions.destory( client_id )
      end
    }
    list_of_closed_sessions
  end

=begin

touch session

  Sessions.touch(client_id)

returns

  true|false

=end

  def self.touch( client_id )
    data = get(client_id)
    return false if !data
    path = "#{@path}/#{client_id}"
    data[:meta][:last_ping] = Time.new.to_i.to_s
    content = data.to_json
    File.open( path + '/session', 'wb' ) { |file|
      file.write content
    }
    true
  end

=begin

get session data

  data = Sessions.get(client_id)

returns

  {
    :user => {
      'id' => 123,
    },
    :meta => {
      :type      => 'websocket',
      :last_ping => time_of_last_ping,
    }
  }

=end

  def self.get( client_id )
    session_dir  = "#{@path}/#{client_id}"
    session_file = "#{session_dir}/session"
    data         = nil
    if !File.exist? session_dir
      destory(client_id)
      Rails.logger.error "missing session directory for '#{client_id}', remove session."
      return
    end
    if !File.exist? session_file
      destory(client_id)
      Rails.logger.errror "missing session file for '#{client_id}', remove session."
      return
    end
    begin
      File.open( session_file, 'rb' ) { |file|
        file.flock( File::LOCK_EX )
        all = file.read
        file.flock( File::LOCK_UN )
        data_json = JSON.parse( all )
        if data_json
          data = symbolize_keys(data_json)
          data[:user] = data_json['user'] # for compat. reasons
        end
      }
    rescue Exception => e
      Rails.logger.error e.inspect
      destory(client_id)
      Rails.logger.error "ERROR: reading session file '#{session_file}', remove session."
      return
    end
    data
  end

=begin

send message to client

  Sessions.send(client_id_of_recipient, data)

returns

  true|false

=end

  def self.send( client_id, data )
    path     = "#{@path}/#{client_id}/"
    filename = "send-#{ Time.new().to_f }"
    check    = true
    count    = 0
    while check
      if File.exist?( path + filename )
        count += 1
        filename = "#{filename}-#{count}"
      else
        check = false
      end
    end
    return false if !File.directory? path
    File.open( path + 'a-' + filename, 'wb' ) { |file|
      file.flock( File::LOCK_EX )
      file.write data.to_json
      file.flock( File::LOCK_UN )
      file.close
    }
    return false if !File.exist?( path + 'a-' + filename )
    FileUtils.mv( path + 'a-' + filename, path + filename )
    true
  end

=begin

send message to recipient client

  Sessions.send_to(user_id, data)

returns

  true|false

=end

  def self.send_to( user_id, data )

    # list all current clients
    client_list = sessions
    client_list.each {|client_id|
      session = Sessions.get(client_id)
      next if !session
      next if !session[:user]
      next if !session[:user]['id']
      next if session[:user]['id'].to_i != user_id.to_i
      Sessions.send( client_id, data )
    }
    true
  end

=begin

send message to all client

  Sessions.broadcast(data)

returns

  true|false

=end

  def self.broadcast( data )

    # list all current clients
    client_list = sessions
    client_list.each {|client_id|
      Sessions.send( client_id, data )
    }
    true
  end

=begin

get messages for client

  messages = Sessions.queue(client_id_of_recipient)

returns

  [
    {
      key1 => 'some data of message 1',
      key2 => 'some data of message 1',
    },
    {
      key1 => 'some data of message 2',
      key2 => 'some data of message 2',
    },
  ]

=end

  def self.queue( client_id )
    path  = "#{@path}/#{client_id}/"
    data  = []
    files = []
    Dir.foreach( path ) {|entry|
      next if entry == '.'
      next if entry == '..'
      files.push entry
    }
    files.sort.each {|entry|
      filename = "#{path}/#{entry}"
      if /^send/.match( entry )
        data.push Sessions.queue_file_read( path, entry )
      end
    }
    data
  end

  def self.queue_file_read( path, filename )
    file_old = "#{path}#{filename}"
    file_new = "#{path}a-#{filename}"
    FileUtils.mv( file_old, file_new )
    all = ''
    File.open( file_new, 'rb' ) { |file|
      all = file.read
    }
    File.delete( file_new )
    JSON.parse( all )
  end

  def self.cleanup
    path = "#{@path}/spool/"
    FileUtils.rm_rf path
    path = "#{@path}/tmp/"
    FileUtils.rm_rf path
  end

  def self.spool_create( msg )
    path = "#{@path}/spool/"
    FileUtils.mkpath path
    file = "#{Time.new.to_f}-#{rand(99_999)}"
    File.open( path + '/' + file, 'wb' ) { |file|
      data = {
        msg: msg,
        timestamp: Time.now.to_i,
      }
      file.write data.to_json
    }
  end

  def self.spool_list( timestamp, current_user_id )
    path = "#{@path}/spool/"
    FileUtils.mkpath path
    data      = []
    to_delete = []
    files     = []
    Dir.foreach( path ) {|entry|
      next if entry == '.'
      next if entry == '..'
      files.push entry
    }
    files.sort.each {|entry|
      filename = "#{path}/#{entry}"
      next if !File.exist?( filename )
      File.open( filename, 'rb' ) { |file|
        all   = file.read
        spool = JSON.parse( all )
        begin
          message_parsed = JSON.parse( spool['msg'] )
        rescue => e
          Rails.logger.error "can't parse spool message: #{ message }, #{ e.inspect }"
          next
        end

        # ignore message older then 48h
        if spool['timestamp'] + (2 * 86_400) < Time.now.to_i
          to_delete.push "#{path}/#{entry}"
          next
        end

        # add spool attribute to push spool info to clients
        message_parsed['spool'] = true

        # only send not already now messages
        if !timestamp || timestamp < spool['timestamp']

          # spool to recipient list
          if message_parsed['recipient'] && message_parsed['recipient']['user_id']

            message_parsed['recipient']['user_id'].each { |user_id|

              next if current_user_id != user_id

              item = {
                type: 'direct',
                message: message_parsed,
              }
              data.push item
            }

          # spool to every client
          else
            item = {
              type: 'broadcast',
              message: message_parsed,
            }
            data.push item
          end
        end
      }
    }
    to_delete.each {|file|
      File.delete(file)
    }
    data
  end

  def self.jobs

    # just make sure that spool path exists
    if !File.exist?( @path )
      FileUtils.mkpath @path
    end

    Thread.abort_on_exception = true
    loop do
      client_ids = sessions
      client_ids.each { |client_id|

        # connection already open, ignore
        next if @@client_threads[client_id]

        # get current user
        session_data = Sessions.get( client_id )
        next if !session_data
        next if !session_data[:user]
        next if !session_data[:user]['id']
        user = User.lookup( id: session_data[:user]['id'] )
        next if !user

        # start client thread
        next if @@client_threads[client_id]

        @@client_threads[client_id] = true
        @@client_threads[client_id] = Thread.new {
          thread_client(client_id)
          @@client_threads[client_id] = nil
          Rails.logger.debug "close client (#{client_id}) thread"
          ActiveRecord::Base.connection.close
        }
        sleep 0.5
      }

      # system settings
      sleep 0.5
    end
  end

=begin

check if thread for client_id is running

  Sessions.thread_client_exists?(client_id)

returns

  thread

=end

  def self.thread_client_exists?(client_id)
    @@client_threads[client_id]
  end

=begin

start client for browser

  Sessions.thread_client(client_id)

returns

  thread

=end

  def self.thread_client(client_id, try_count = 0, try_run_time = Time.now)
    Rails.logger.debug "LOOP #{client_id} - #{try_count}"
    begin
      Sessions::Client.new(client_id)
    rescue => e
      Rails.logger.error "thread_client #{client_id} exited with error #{ e.inspect }"
      Rails.logger.error e.backtrace.join("\n  ")
      sleep 10
      begin
        ActiveRecord::Base.connection_pool.release_connection
      rescue => e
        Rails.logger.error "Can't reconnect to database #{ e.inspect }"
      end

      try_run_max = 10
      try_count += 1

      # reset error counter if to old
      if try_run_time + ( 60 * 5 ) < Time.now
        try_count = 0
      end
      try_run_time = Time.now

      # restart job again
      if try_run_max > try_count
        thread_client(client_id, try_count, try_run_time)
      else
        raise "STOP thread_client for client #{client_id} after #{try_run_max} tries"
      end
    end
    Rails.logger.debug "/LOOP #{client_id} - #{try_count}"
  end

  def self.symbolize_keys(hash)
    hash.each_with_object({}) {|(key, value), result|
      new_key = case key
                when String then key.to_sym
                else key
                end
      new_value = case value
                  when Hash then symbolize_keys(value)
                  else value
                  end
      result[new_key] = new_value
    }
  end

end
