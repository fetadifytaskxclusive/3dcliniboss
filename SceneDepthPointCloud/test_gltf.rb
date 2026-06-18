require 'net/http'
require 'json'

uri = URI('https://api.github.com/search/repositories?q=gltf+export+language:swift&sort=stars')
response = Net::HTTP.get(uri)
json = JSON.parse(response)
json['items'].take(3).each do |repo|
  puts "#{repo['name']} - #{repo['description']} (#{repo['html_url']})"
end
