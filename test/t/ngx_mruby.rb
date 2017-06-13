##
# ngx_mruby test
#

# Temporary solution for https://github.com/iij/mruby-io/issues/75
begin
  `/bin/true`
rescue NotImplementedError => e
  module Kernel
    def `(c); IO.popen(c) { |io| io.read }; end
  end
end

def http_host(port = 58080)
  "127.0.0.1:#{port}"
end

def base(port = 58080)
  "http://#{http_host(port)}"
end

def base_ssl(port)
  "https://localhost:#{port}"
end

class NginxFeatures
  attr_reader :version_string
  def initialize(nginx_version)
    @version_string = nginx_version
    @major, @minor, @patch = @version_string.split(".").map {|v| v.to_i}
    p "version_string=#{@version_string}, major=#{@major}, minor=#{@minor}, patch=#{@patch}"
  end
  def is_upstream_supported?
    # Nginx::Upstream only works with nginx 1.7 or later. See ngx_http_mruby_module.h
    @minor > 6
  end
  def is_stream_supported?
    # 1.9.6 or later
    @minor >= 10 || (@minor == 9 && @patch >= 6)
  end
end

t = SimpleTest.new "ngx_mruby test"

nginx_features = NginxFeatures.new(HttpRequest.new.get(base + '/nginx-version')["body"])

t.assert('ngx_mruby', 'location /mruby') do
  res = HttpRequest.new.get base + '/mruby'
  t.assert_equal 'Hello ngx_mruby world!', res["body"]
end

t.assert('ngx_mruby', 'location /proxy') do
  res = HttpRequest.new.get base + '/proxy'
  t.assert_equal 'proxy test ok', res["body"]
end

t.assert('ngx_mruby', 'location /vars') do
  res = HttpRequest.new.get base + '/vars'
  t.assert_equal 'host => 127.0.0.1 foo => mruby', res["body"]
end

t.assert('ngx_mruby', 'location /redirect') do
  res = HttpRequest.new.get base + '/redirect'
  t.assert_equal 301, res.code
  t.assert_equal 'http://ngx.mruby.org', res["location"]
end

t.assert('ngx_mruby', 'location /redirect/internal') do
  res = HttpRequest.new.get base + '/redirect/internal'
  t.assert_equal 'host => 127.0.0.1 foo => mruby', res["body"]
end

t.assert('ngx_mruby', 'location /inter_var_file') do
  res = HttpRequest.new.get base + '/inter_var_file'
  t.assert_equal 'fuga => 200 hoge => 400 hoge => 800', res["body"]
end

t.assert('ngx_mruby', 'location /inter_var_inline') do
  res = HttpRequest.new.get base + '/inter_var_inline'
  t.assert_equal 'fuga => 100 hoge => 200 hoge => 400', res["body"]
end

t.assert('ngx_mruby - output filter', 'location /filter_dynamic_arg') do
  res = HttpRequest.new.get base + '/filter_dynamic_arg'
  t.assert_equal 'output filter: static', res["body"]
end

t.assert('ngx_mruby - output filter', 'location /filter_dynamic_arg?hoge=fuga') do
  res = HttpRequest.new.get base + '/filter_dynamic_arg?hoge=fuga'
  t.assert_equal 'output filter: hoge=fuga', res["body"]
  t.assert_equal 'hoge=fuga', res["x-new-header"]
end

t.assert('ngx_mruby - output filter', 'location /filter_dynamic_arg_file?hoge=fuga') do
  res = HttpRequest.new.get base + '/filter_dynamic_arg_file?hoge=fuga'
  t.assert_equal 'output filter: hoge=fuga', res["body"]
  t.assert_equal 'hoge=fuga', res["x-new-header"]
end

t.assert('ngx_mruby - Nginx::Connection#{local_ip,local_port}', 'location /server_ip_port') do
  res = HttpRequest.new.get base + '/server_ip_port'
  t.assert_equal '127.0.0.1:58080', res["body"]
end

t.assert('ngx_mruby - Nginx::Connection#{remote_ip,local_port}', 'location /client_ip') do
  res = HttpRequest.new.get base + '/client_ip'
  t.assert_equal '127.0.0.1', res["body"]
end

t.assert('ngx_mruby', 'location /header') do
  res1 = HttpRequest.new.get base + '/header'
  res2 = HttpRequest.new.get base + '/header', nil, {"X-REQUEST-HEADER" => "hoge"}

  t.assert_equal "X-REQUEST-HEADER not found", res1["body"]
  t.assert_equal "nothing", res1["x-response-header"]
  t.assert_equal "X-REQUEST-HEADER found", res2["body"]
  t.assert_equal "hoge", res2["x-response-header"]
end

t.assert('ngx_mruby', 'location /header/internal') do
  res = HttpRequest.new.get base + '/header/internal'
  t.assert_equal "hoge", res["x-internal-header"]
end

t.assert('ngx_mruby', 'location /headers_out_delete') do
  res = HttpRequest.new.get base + '/headers_out_delete'
  range = (1..53).map(&:to_s)
  expect_deleted = %w(2 1 22 21 25 42 41 43 47 40 51 53 52)
  expect_existing = range - expect_deleted
  expect_deleted.each do |n|
    t.assert_equal nil, res["ext-header#{n}"], n
  end
  expect_existing.each do |n|
    t.assert_equal 'foo', res["ext-header#{n}"], n
  end
end

t.assert('ngx_mruby', 'location /headers_in_delete') do
  res = HttpRequest.new.get base + '/headers_in_delete', nil, {"X-REQUEST-HEADER" => "hoge"}
  t.assert_equal "hoge", res["x-internal-header"]
  t.assert_equal "X-REQUEST-HEADER is nil", res["body"]
end

t.assert('ngx_mruby - mruby_add_handler', '*\.rb') do
  res = HttpRequest.new.get base + '/add_handler.rb'
  t.assert_equal 'add_handler', res["body"]
end

t.assert('ngx_mruby - all instance test', 'location /all_instance') do
  res = HttpRequest.new.get base + '/all_instance'
  t.assert_equal "OK", res["x-inst-test"]
end

t.assert('ngx_mruby', 'location /request_method') do
  res = HttpRequest.new.get base + '/request_method'
  t.assert_equal "GET", res["body"]
  res = HttpRequest.new.post base + '/request_method'
  t.assert_equal "POST", res["body"]
  res = HttpRequest.new.head base + '/request_method'
  t.assert_equal "head", res["x-method"]
end

t.assert('ngx_mruby - Kernel.server_name', 'location /kernel_servername') do
  res = HttpRequest.new.get base + '/kernel_servername'
  t.assert_equal 'NGINX', res["body"]
end

# see below url:
# https://github.com/matsumotory/ngx_mruby/wiki/Class-and-Method#refs-nginx-core-variables
t.assert('ngx_mruby - Nginx::Var', 'location /nginx_var?name=name') do
  t.assert_equal '/nginx_var', HttpRequest.new.get(base + '/nginx_var?name=uri')["body"]
  t.assert_equal 'HTTP/1.0', HttpRequest.new.get(base + '/nginx_var?name=server_protocol')["body"]
  t.assert_equal 'http', HttpRequest.new.get(base + '/nginx_var?name=scheme')["body"]
  t.assert_equal '127.0.0.1', HttpRequest.new.get(base + '/nginx_var?name=remote_addr')["body"]
  t.assert_equal '58080', HttpRequest.new.get(base + '/nginx_var?name=server_port')["body"]
  t.assert_equal '127.0.0.1', HttpRequest.new.get(base + '/nginx_var?name=server_addr')["body"]
  t.assert_equal 'GET /nginx_var?name=request HTTP/1.0', HttpRequest.new.get(base + '/nginx_var?name=request')["body"]
  t.assert_equal 'name=query_string', HttpRequest.new.get(base + '/nginx_var?name=query_string')["body"]
end

t.assert('ngx_mruby - Nginx.return', 'location /service_unavailable') do
  res = HttpRequest.new.get base + '/service_unavailable'
  t.assert_equal 503, res.code
end

t.assert('ngx_mruby - Nginx.return 200 and body', 'location /return_and_body') do
  res = HttpRequest.new.get base + '/return_and_body'
  t.assert_equal "body", res["body"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - Nginx.return 200 dont have body', 'location /return_and_error') do
  res = HttpRequest.new.get base + '/return_and_error'
  t.assert_equal 500, res.code
end

t.assert('ngx_mruby - raise error with no response body', 'location /raise_and_no_response') do
  res = HttpRequest.new.get base + '/raise_and_no_response'
  t.assert_equal 500, res.code
end

t.assert('ngx_mruby - request_body', 'location /request_body_manual') do
  res = HttpRequest.new.post base + '/request_body_manual', "request body manual test"
  t.assert_equal "request body manual test", res["body"]
end

t.assert('ngx_mruby - request_body', 'location /request_body') do
  res = HttpRequest.new.post base + '/request_body', "request body test"
  t.assert_equal "request body test", res["body"]
end

t.assert('ngx_mruby - get server class name', 'location /server_class') do
  res = HttpRequest.new.get base + '/server_class'
  t.assert_equal "Nginx", res["body"]
end

t.assert('ngx_mruby - add response header in output_filter', 'location /output_filter_header') do
  res = HttpRequest.new.get base + '/output_filter_header/index.html'
  t.assert_equal "output_filter_header\n", res["body"]
  t.assert_equal "new_header", res["x-add-new-header"]
end

t.assert('ngx_mruby - add response header in output_header_filter', 'location /output_header_filter') do
  res = HttpRequest.new.head base + '/output_header_filter/index.html'
  t.assert_equal "new_header", res["x-add-new-header"]
end

t.assert('ngx_mruby - update built-in response header in output_filter', 'location /output_filter_builtin_header') do
  res = HttpRequest.new.get base + '/output_filter_builtin_header/index.html'
  t.assert_equal "output_filter_builtin_header\n", res["body"]
  t.assert_equal "ngx_mruby", res["server"]
end

t.assert('ngx_mruby - update built-in response header in http context', 'location /mruby') do
  # content phase
  res = HttpRequest.new.get base + '/mruby'
  t.assert_equal "global_ngx_mruby", res["server"]
  # proxy phase
  res = HttpRequest.new.get base + '/proxy'
  t.assert_equal "global_ngx_mruby", res["server"]
  # access phase
  res = HttpRequest.new.get base + '/headers_in_delete'
  t.assert_equal "global_ngx_mruby", res["server"]
  # redirect phase
  res = HttpRequest.new.get base + '/redirect'
  t.assert_equal "global_ngx_mruby", res["server"]
  # output filter phase, already set other Server header
  res = HttpRequest.new.get base + '/output_filter_builtin_header/index.html'
  t.assert_not_equal "global_ngx_mruby", res["server"]
  # return error
  res = HttpRequest.new.get base + '/return_and_error'
  t.assert_equal "global_ngx_mruby", res["server"]
end

t.assert('ngx_mruby - sub_request? check', 'location /sub_request_check') do
  res = HttpRequest.new.get base + '/sub_request_check'
  t.assert_equal "false", res["body"]
end

t.assert('ngx_mruby - bug; mruby_post_read_handler not running in 1.18.3+', 'location /issue_210') do
  res = HttpRequest.new.get base + '/issue_210'
  t.assert_equal "fuga", res["hoge"]
  t.assert_equal "hello", res["body"]
end

t.assert('ngx_mruby - bug; mruby_post_read_handler not running in 1.18.3+ for file code', 'location /issue_210_2') do
  res = HttpRequest.new.get base + '/issue_210_2'
  t.assert_equal "fuga", res["hoge"]
  t.assert_equal "hello2", res["body"]
end

if nginx_features.is_upstream_supported?
  t.assert('ngx_mruby - upstream keepalive', 'location /upstream-keepalive') do
    res = HttpRequest.new.get base + '/upstream-keepalive'
    t.assert_equal "true", res["body"]
  end
end

t.assert('ngx_mruby - authority', 'location /authority') do
  res = HttpRequest.new.get base + '/authority', nil, {"Host" => http_host}
  t.assert_equal http_host, res["body"]
end

t.assert('ngx_mruby - hostname', 'location /hostname') do
  res = HttpRequest.new.get base + '/hostname', nil, {"Host" => http_host}
  t.assert_equal "127.0.0.1", res["body"]
end

t.assert('ngx_mruby - Var#exist?', 'location /var_exist') do
  res = HttpRequest.new.get base + '/var_exist'
  t.assert_equal "false", res["body"]

  res = HttpRequest.new.get base + '/var_exist?foo=bar'
  t.assert_equal "true", res["body"]
end

t.assert('ngx_mruby - rack base', 'location /rack_base') do
  res = HttpRequest.new.get base + '/rack_base'
  t.assert_equal "rack body", res["body"]
  t.assert_equal "foo", res["x-hoge"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base', 'location /rack_base1') do
  res = HttpRequest.new.get base + '/rack_base1'
  t.assert_equal "rack body", res["body"]
  t.assert_equal "foo", res["x-hoge"]
  t.assert_equal "hoge", res["x-foo"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base', 'location /rack_base2') do
  res = HttpRequest.new.get base + '/rack_base2'
  t.assert_equal "rack body", res["body"]
  t.assert_equal "foo", res["x-hoge"]
  t.assert_equal "hoge", res["x-foo"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base', 'location /rack_base3') do
  res = HttpRequest.new.get base + '/rack_base3'
  t.assert_equal 404, res.code
end

t.assert('ngx_mruby - rack base', 'location /rack_base4') do
  res = HttpRequest.new.get base + '/rack_base4'
  t.assert_equal 500, res.code
end

t.assert('ngx_mruby - rack base', 'location /rack_base_env') do
  res = HttpRequest.new.get base + '/rack_base_env?a=1&b=1', nil, {"Host" => "ngx.example.com:58080", "x-hoge" => "foo"}
  body = JSON.parse res["body"]
  puts body

  t.assert_equal "GET", body["REQUEST_METHOD"]
  t.assert_equal "", body["SCRIPT_NAME"]
  t.assert_equal "/rack_base_env", body["PATH_INFO"]
  t.assert_equal "/rack_base_env?a=1&b=1", body["REQUEST_URI"]
  t.assert_equal "a=1&b=1", body["QUERY_STRING"]
  t.assert_equal "ngx.example.com", body["SERVER_NAME"]
  t.assert_equal "127.0.0.1", body["SERVER_ADDR"]
  t.assert_equal "58080", body["SERVER_PORT"]
  t.assert_equal "127.0.0.1", body["REMOTE_ADDR"]
  t.assert_equal "http", body["rack.url_scheme"]
  t.assert_false body["rack.multithread"]
  t.assert_true body["rack.multiprocess"]
  t.assert_false body["rack.run_once"]
  t.assert_false body["rack.hijack?"]
  t.assert_equal "NGINX", body["server.name"]
  t.assert_equal nginx_features.version_string, body["server.version"]
  t.assert_equal "*/*", body["HTTP_ACCEPT"]
  t.assert_equal "close", body["HTTP_CONNECTION"]
  t.assert_equal "ngx.example.com:58080", body["HTTP_HOST"]
  t.assert_equal "foo", body["HTTP_X_HOGE"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base', 'method POST, location /rack_base_env') do
  req_body = 'Hello'
  res = HttpRequest.new.post base + '/rack_base_env', req_body, {"Content-Type" => "text/plain; charset=us-ascii", "Content-Length" => req_body.size}
  res_body = JSON.parse res["body"]
  puts res_body

  t.assert_equal "POST", res_body["REQUEST_METHOD"]
  t.assert_equal "text/plain; charset=us-ascii", res_body["CONTENT_TYPE"]
  t.assert_equal req_body.size.to_s, res_body["CONTENT_LENGTH"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base auth ok', 'location /rack_base_2phase') do
  res = HttpRequest.new.get base + '/rack_base_2phase', nil, {"auth-token" => "aaabbbccc"}
  t.assert_equal "OK", res["body"]
  t.assert_equal "127.0.0.1", res["x-client-ip"]
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base auth ng', 'location /rack_base_2phase') do
  res = HttpRequest.new.get base + '/rack_base_2phase', nil, {"auth-token" => "cccbbbaaa"}
  t.assert_equal 403, res.code
end

t.assert('ngx_mruby - rack base push', 'location /rack_base_push/index.txt') do
  res = HttpRequest.new.get base + '/rack_base_push/index.txt'
  t.assert_equal 200, res.code
  t.assert_equal "</index.js>; rel=preload", res["link"]
end

t.assert('ngx_mruby - rack base logger', 'location /rack_base_logger') do
  res = HttpRequest.new.get base + '/rack_base_logger'
  # just want to make sure if logger methods don't throw any exception.
  t.assert_equal 200, res.code
end

t.assert('ngx_mruby - rack base input', 'location /rack_base_input') do
  res = HttpRequest.new.get base + '/rack_base_input'
  t.assert_equal 200, res.code
  t.assert_equal "GET:", res["body"]

  res = HttpRequest.new.post(base + '/rack_base_input', 'Foo')
  t.assert_equal 200, res.code
  t.assert_equal "POST:Foo", res["body"]

  res = HttpRequest.new.put(base + '/rack_base_input', 'Bar')
  t.assert_equal 200, res.code
  t.assert_equal "PUT:Bar", res["body"]
end

t.assert('ngx_mruby - rack base errorpage', 'location /rack_base_errorpage') do
  res = HttpRequest.new.get base + '/rack_base_errorpage'
  t.assert_equal 401, res.code
  t.assert_equal "THIS IS AN ERROR MESSAGE FOR 401", res["body"]
end

t.assert('ngx_mruby - multipul request headers', 'location /multi_headers_in') do
  res = HttpRequest.new.get base + '/multi_headers_in', nil, {"hoge" => "foo"}
  t.assert_equal 200, res.code
  t.assert_equal '["foo", "fuga"]', res["body"]
end

t.assert('ngx_mruby - multipul response headers', 'location /multi_headers_out') do
  res = HttpRequest.new.get base + '/multi_headers_out'
  t.assert_equal 200, res.code
  t.assert_equal '["foo", "fuga"]', res["body"]
  t.assert_equal ["foo", "fuga"], res["hoge"]
end

t.assert('ngx_mruby - fix bug issue 155', 'location /fix-bug-issue-155') do
  res = HttpRequest.new.get base + '/fix-bug-issue-155'
  t.assert_equal 200, res.code
  p res
  t.assert_equal '["abc=123", "foo=bar"]', res["body"]
  t.assert_equal ["abc=123", "foo=bar"], res['set-cookies']
end

t.assert('ngx_mruby - get uri_args', 'location /get_uri_args') do
  res = HttpRequest.new.get base + '/get_uri_args/?k=v'
  t.assert_equal "k:v\n", res["body"]
end

t.assert('ngx_mruby - set uri_args', 'location /set_uri_args') do
  res = HttpRequest.new.get base + '/set_uri_args'
  t.assert_equal "pass=ngx_mruby\n", res['body']
end

t.assert('ngx_mruby - get post_args', 'location /get_post_args') do
  res = HttpRequest.new.post base + '/get_post_args', 'foo=bar&bar=buzz'
  t.assert_equal "foo:bar\nbar:buzz\n", res['body']
end

t.assert('ngx_mruby - ssl local port') do
  res = `curl -k #{base_ssl(58082) + '/local_port'}`
  t.assert_equal '58082', res
end

t.assert('ngx_mruby - ssl certificate changing') do
  res = `curl -k #{base_ssl(58082) + '/'}`
  t.assert_equal 'ssl test ok', res
  res = `openssl s_client -servername localhost -connect localhost:58082 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not | sed -e "s/://" | awk '{print (res = $6 - res)}' | tail -n 1`.chomp
  t.assert_equal "1", res
  res = `openssl s_client -servername hogehoge -connect 127.0.0.1:58082 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not`.chomp
  t.assert_equal "", res
end

t.assert('ngx_mruby - ssl certificate changing using data instead of file') do
  res = `curl -k #{base_ssl(58083) + '/'}`
  t.assert_equal 'ssl test ok', res
  res = `openssl s_client -servername localhost -connect localhost:58083 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not | sed -e "s/://" | awk '{print (res = $6 - res)}' | tail -n 1`.chomp
  t.assert_equal "1", res
  res = `openssl s_client -servername hogehoge -connect 127.0.0.1:58083 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not`.chomp
  t.assert_equal "", res
end

t.assert('ngx_mruby - ssl certificate changing - reading handler from file without caching') do
  fname = File.join(ENV['NGINX_INSTALL_DIR'], 'html/set_ssl_cert_and_key.rb')

  res = `curl -k #{base_ssl(58085) + '/'}`
  t.assert_equal 'ssl test ok', res

  content = File.read(fname).gsub('#{ssl.servername}', 'localhost')
  File.open(fname, 'w') { |f| f.puts content }

  cmd_l = "openssl s_client -servername localhost -connect localhost:58085 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not | sed -e 's/://' | awk '{print (res = $6 - res)}' | tail -n 1"
  cmd_h = "openssl s_client -servername hogehoge -connect 127.0.0.1:58085 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not | sed -e 's/://' | awk '{print (res = $6 - res)}' | tail -n 1"
  t.assert_equal "1", `#{cmd_l}`.chomp
  t.assert_equal "1", `#{cmd_h}`.chomp

  content = File.read(fname).gsub('localhost', '#{ssl.servername}')
  File.open(fname, 'w') { |f| f.puts content }

  t.assert_equal "1", `#{cmd_l}`.chomp
  t.assert_equal "", `#{cmd_h}`.chomp
end

t.assert('ngx_mruby - ssl certificate changing - reading handler from file with caching') do
  fname = File.join(ENV['NGINX_INSTALL_DIR'], 'html/set_ssl_cert_and_key.rb')

  res = `curl -k #{base_ssl(58086) + '/'}`
  t.assert_equal 'ssl test ok', res

  content = File.read(fname).gsub('#{ssl.servername}', 'localhost')
  File.open(fname, 'w') { |f| f.puts content }

  cmd_l = "openssl s_client -servername localhost -connect localhost:58086 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not | sed -e 's/://' | awk '{print (res = $6 - res)}' | tail -n 1"
  cmd_h = "openssl s_client -servername hogehoge -connect 127.0.0.1:58086 < /dev/null 2> /dev/null | openssl x509 -text  | grep Not"
  t.assert_equal "1", `#{cmd_l}`.chomp
  t.assert_equal "", `#{cmd_h}`.chomp

  content = File.read(fname).gsub('localhost', '#{ssl.servername}')
  File.open(fname, 'w') { |f| f.puts content }

  t.assert_equal "1", `#{cmd_l}`.chomp
  t.assert_equal "", `#{cmd_h}`.chomp
end

t.assert('ngx_mruby - Nginx::SSL.errlogger') do
  `openssl s_client -servername localhost -connect localhost:58087 < /dev/null 2>/dev/null`
  error_log = File.read File.join(ENV['NGINX_INSTALL_DIR'], 'logs/error.log');
  t.assert_true error_log.include? 'Servername is localhost while SSL handshaking'
end

t.assert('ngx_mruby - get ssl server name') do
  res = `echo "GET /servername" | openssl s_client -ign_eof -connect localhost:58088 2>/dev/null | sed -n '$s/closed$//p'`
  t.assert_equal "servername is empty", res.chomp
  res = `echo "GET /servername" | openssl s_client -ign_eof -connect localhost:58088 -servername ngx.example.com 2>/dev/null | sed -n '$s/closed$//p'`
  t.assert_equal "ngx.example.com", res.chomp
end

t.assert('ngx_mruby - issue_172', 'location /issue_172') do
  res = HttpRequest.new.get base + '/issue_172/index.html'
  expect_content = 'hello world'.upcase
  t.assert_equal expect_content, res["body"]
  t.assert_equal expect_content.length, res["content-length"].to_i
end

t.assert('ngx_mruby - issue_172_2', 'location /issue_172_2') do
  res = HttpRequest.new.get base + '/issue_172_2/'
  expect_content = 'hello world'.upcase
  t.assert_equal expect_content, res["body"]
  t.assert_equal expect_content.length, res["content-length"].to_i
end

t.assert('ngx_mruby - Nginx FALSE TRUE value', 'location /nginx_false_true') do
  res = HttpRequest.new.get base + '/nginx_false_true/'
  t.assert_equal "01", res["body"]
end

t.assert('ngx_mruby - Throw my own exception for issue 238', 'location /issue_238') do
  res = HttpRequest.new.get base + '/issue_238'
  t.assert_equal 500, res.code
end

t.assert('ngx_mruby - access_handler in server scope', 'location /access_handler_in_server_scope') do
  res = HttpRequest.new.get base(58084) + '/access_handler_in_server_scope/'
  t.assert_equal 403, res["code"]
end

t.assert('ngx_mruby - override access_handler in server scope', 'location /override_access_handler_in_server_scope') do
  res = HttpRequest.new.get base(58084) + '/override_access_handler_in_server_scope/'
  t.assert_equal 200, res["code"]
  t.assert_equal "OK", res["body"]
end

t.assert('ngx_mruby - fix bug: body filter transfer closed with any bytes remaining to read', 'location /image_filter') do
  res = HttpRequest.new.get base + '/image_filter'
  t.assert_equal 1160568, res["body"].size
  t.assert_equal 1160568, res["content-length"].to_i
end

t.assert('ngx_mruby - BUG: request_body issue 268', 'location /issue-268') do
  #res = HttpRequest.new.post base + '/issue-268', '{"hello": "ngx_mruby"}'
  #t.assert_equal '{"hello": "ngx_mruby"}', res
  res = `./test/t/issue-268-test.rb`.split("\r\n\r\n")[1]
  t.assert_equal %({\"hello\": \"ngx_mruby\"}\n), res
end

t.assert('ngx_mruby - backtrace log', 'location /backtrace') do
  res = HttpRequest.new.get base + '/backtrace'
  t.assert_equal 500, res["code"]

  fname = File.join(ENV['NGINX_INSTALL_DIR'], 'logs/error.log')
  found = 0
  File.open(fname) {|f| f.each_line {|line| found += 1 if line.index('/nginx/html/backtrace.rb:') } }
  t.assert_equal 4, found
end

t.assert('ngx_mruby - with auth_request', 'location /protected_resource') do
  body = nil
  res = HttpRequest.new.get base + '/protected_resource'
  t.assert_equal 401, res["code"]

  res = HttpRequest.new.get(base + '/protected_resource', body, {"Authorization" => "Bearer hoge"})
  t.assert_equal 200, res["code"]
  t.assert_equal "This is a protected resource", res["body"]

  res = HttpRequest.new.get(base + '/protected_resource', body, {"Authorization" => "Bearer blahblahblah"})
  t.assert_equal 200, res["code"]
  t.assert_equal "This is a protected resource", res["body"]

  res = HttpRequest.new.get(base + '/protected_resource', body, {"Authorization" => "Bearer boofoowoo"})
  t.assert_equal 200, res["code"]
  t.assert_equal "This is a protected resource", res["body"]
end

if nginx_features.is_stream_supported?

  base1 = "http://127.0.0.1:12345"
  base2 = "http://127.0.0.1:12346"
  base3 = "http://127.0.0.1:12348"
  base4 = "http://127.0.0.1:12349"

  t.assert('ngx_mruby - stream tcp load balancer', '127.0.0.1:12345 to 127.0.0.1:58080 which changed from 127.0.0.1:58081 by mruby') do
    res = HttpRequest.new.get(base1 + '/mruby')
    t.assert_equal 'Hello ngx_mruby world!', res["body"]
  end
  t.assert('ngx_mruby - stream tcp load balancer', '127.0.0.1:12346 to 127.0.0.1:58081 which changed from 127.0.0.1:58080 by mruby') do
    res = HttpRequest.new.get(base2 + '/')
    t.assert_equal 'proxy test ok', res["body"]
  end
  t.assert('ngx_mruby - stream tcp port') do
    res = HttpRequest.new.get(base3 + '/mruby')
    t.assert_equal 'Hello ngx_mruby world!', res["body"]
  end
  t.assert('ngx_mruby - stream tcp ip port text') do
    res = HttpRequest.new.get(base4 + '/mruby')
    t.assert_equal 'Hello ngx_mruby world!', res["body"]
  end
end

t.report
