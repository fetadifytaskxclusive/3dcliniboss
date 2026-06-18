require 'net/http'
require 'json'

uri = URI('https://api.github.com/search/repositories?q=gltf+export+language:swift')
req = Net::HTTP::Get.new(uri)
req['User-Agent'] = 'Mozilla/5.0'

res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
  http.request(req)
}

JSON.parse(res.body)['items']&.first(5)&.each do |item|
  puts "#{item['name']} - #{item['description']}"
end
