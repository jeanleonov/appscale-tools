require 'yaml'
require 'thread'
require 'net/ssh'

$mutex = Mutex.new

def validate_credentials(user,pass1,pass2)
  if user.nil? or user.length == 0
    return [ false, "Administrator username not provided" ]
  elsif pass1.nil? or pass2.nil? or pass1.length == 0 or pass2.length == 0
    return [ false, "Administrator password not provided" ]
  elsif pass1 != pass2
    return [ false, "Password entries do not match" ]
  elsif pass1.length < 6
    return [ false, "Password must contain at least 6 characters" ]
  else
    return [ true, '' ]
  end
end

def validate_ssh_credentials(keyname, root_password, ips_yaml)
  if keyname.nil? or keyname.length == 0
    return [ false, "AppScale key name not provided" ]
  elsif root_password.nil? or root_password == 0
    return [ false, "Root password for AppScale machines not provided" ]
  else
    # Randomly pick a server and try to connect to it via SSH using the
    # provided credentials. This will guard againt invalid root passwords
    # entered by the user and any obvious network level issues which might
    # prevent AppsCake from connecting to the specified machines. The test
    # assumes that all hosts can be accessed using the same root password
    # and they are on the same network (if one is reachable, then all are
    # reachable) which is the case for most typical AppScale deployments.
    # In scenarios where the above assumption is not the case (i.e. some
    # machines are reachable and some are not) the test may pass, but the 
    # final deployment may fail. These runtime errors will go to the deployment 
    # logs generated by AppsCake per each deployment which can also be accessed 
    # over the web.
    node_layout = NodeLayout.new(ips_yaml, { :database => "cassandra" } )
    ips = node_layout.nodes.collect { |node| node.id }
    begin
      Net::SSH.start(ips[0], 'root', :password => root_password, :timeout => 10) do |ssh|
        ssh.exec('ls')
      end
    rescue Timeout::Error
      return [ false, "Connection timed out for #{ips[0]}" ]
    rescue Errno::EHOSTUNREACH
      return [ false, "Host unreachable error for #{ips[0]}" ]
    rescue Errno::ECONNREFUSED
      return [ false, "Connection refused for #{ips[0]}" ]
    rescue Net::SSH::AuthenticationFailed
      return [ false, "Authentication failed for #{ips[0]} - Please ensure that the specified root password is correct" ]
    rescue Exception=>e
      return [ false, "Unexpected runtime error connecting to #{ips[0]}" ]
    end

    return [ true, '' ]
  end
end

def validate_yaml(yaml_str)
  if yaml_str.nil? or yaml_str.length == 0
    return [ false, "ips.yaml configuration not provided" ]
  end

  yaml = YAML.load(yaml_str)
  critical_roles = %w[ appengine loadbalancer database login shadow zookeeper ]
  aggregate_roles = { 
    'master' => %w[ shadow loadbalancer zookeeper login ],
    'controller' => %w[ shadow loadbalancer zookeeper database login ],
    'servers' => %w[ appengine database loadbalancer ]
  }
  optional_roles = %w[ open memcache ]
  
  success_result = ''
  yaml.each do |symbol,value|
    role = symbol.to_s
    if !critical_roles.include?role and !aggregate_roles.has_key?role and !optional_roles.include?role
      return [ false, "Unknown AppScale server role: #{role}" ]
    else
      critical_roles.delete_if { |r| r == role or (aggregate_roles.has_key?role and aggregate_roles[role].include?r) }
      success_result += "<p>#{role}</p><ul>"
      if value.kind_of?(Array)
        value.each do |val|
          success_result += "<li>#{val}</li>"
        end
      else
        success_result += "<li>#{value}</li>"
      end
      success_result += '</ul>'
    end
  end

  if critical_roles.length > 0
    result = "Following required roles are not configured: "
    critical_roles.each do |role|
      result += "#{role}, "
    end   
    return [ false, result[0..-3] ]
  end

  [ true, success_result ]
end

def locked?
  $mutex.synchronize do
    return File.exists?('appscake.lock')
  end
end

def lock
  $mutex.synchronize do
    if !File.exists?('appscake.lock')
      File.open('appscake.lock','w') do |file|
        file.write('AppsCake.lock')
      end
      return true
    else
      return false
    end
  end
end

def unlock
  $mutex.synchronize do
    if File.exists?('appscake.lock')
      File.delete('appscake.lock')
      return true
    else
      return false
    end
  end
end

def deploy(options)
  30.times do |i|
    puts "Deploying..."
    sleep(1)
  end
end

def add_key(options)
  puts "Generatig RSA keys..."
end

def stfu(timestamp)
    begin
      orig_stderr = $stderr.clone
      orig_stdout = $stdout.clone
      $stderr.reopen File.new("public/logs/deploy-#{timestamp}.log", "w")
      $stdout.reopen File.new("public/logs/deploy-#{timestamp}.log", "w")
      retval = yield
    rescue Exception => e
      $stdout.reopen orig_stdout
      $stderr.reopen orig_stderr
      raise e
    ensure
      $stdout.reopen orig_stdout
      $stderr.reopen orig_stderr
    end
    retval
end
