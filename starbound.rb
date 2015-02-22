require 'sinatra'
require 'json'
require 'rethinkdb'
require 'elasticsearch'
require 'redis'
include RethinkDB::Shortcuts

RDB_CONFIG = {
  :host => ENV['RETHINKURL'], 
  :port => 28015,
  :db   => ENV['RETHINKDB']
}

r = RethinkDB::RQL.new

$elasticsearch = Elasticsearch::Client.new host: ENV['BONSAI_URL']

$redis = Redis.new(url: ENV['REDISCLOUD_URL'])

configure do
  set :db, RDB_CONFIG[:db]
  begin
    connection = r.connect(:host => RDB_CONFIG[:host],
      :port => RDB_CONFIG[:port])
  rescue Exception => err
    puts "Cannot connect to RethinkDB database #{RDB_CONFIG[:host]}:#{RDB_CONFIG[:port]} (#{err.message})"
    Process.exit(1)
  end
end

before do
  begin
    @rdb_connection = r.connect(:host => RDB_CONFIG[:host], :port =>
      RDB_CONFIG[:port], :db => settings.db)
    rescue Exception => err
      logger.error "Cannot connect to RethinkDB database #{RDB_CONFIG[:host]}:#{RDB_CONFIG[:port]} (#{err.message})"
      halt 501, 'This page could look nicer, unfortunately the error is the same: database not available.'
    end
  end

  after do
  begin
    @rdb_connection.close if @rdb_connection
  rescue
    logger.warn "Couldn't close connection"
  end
end

helpers do
  def rarity(text)
    if text
    text.downcase
    else
    end
  end
end

get '/' do
  erb :index, :format => :html5
end

get '/stats' do
  @total_searches = format_number($redis.get('searches'))
  @stable_item_count = format_number($elasticsearch.indices.stats['_all']['primaries']['docs']['count'])

  @searches = $redis.zrevrange('search_terms', 0,9, with_scores: true).map{|v| {term: v.first, score: sprintf('%.0f', v.last)}}

  erb :stats, :format => :html5
end

get '/all' do
  @items = r.table('items').order_by(:index => 'itemName').limit(200).run(@rdb_connection)

  @total_items = r.table('items').count().run(@rdb_connection).to_i

  @current_page = 1
  @next_page = 2
  @prev_page = 0
  @last_page = r.table('items').count().run(@rdb_connection).to_i / 200

  erb :all, :format => :html5
end

get '/all/:page' do
  if params[:page] == 1
    count = 0
  else
    count = params[:page].to_i * 200
  end

  @items = r.table('items').order_by(:index => 'itemName').skip(count).limit(200).run(@rdb_connection)

  @total_items = r.table('items').count().run(@rdb_connection).to_i - 200

  @current_page = params[:page].to_i
  @next_page = params[:page].to_i + 1
  @prev_page = params[:page].to_i - 1
  @last_page = r.table('items').count().run(@rdb_connection).to_i / 200

  erb :all, :format => :html5
end

get '/api/search/:query' do
  clean_query = params[:query].gsub(/[^0-9a-z ]/i, '')

  search = $elasticsearch.search q: "*#{clean_query}*", size:100

  results = search['hits']['hits'].map{|k,v| {itemName: k['_source']['itemName'], shortdescription: k['_source']['shortdescription'], description: k['_source']['description'], inventoryIcon: k['_source']['inventoryIcon'], type: k['_source']['type'], rarity: k['_source']['rarity']}}

  $redis.zincrby('search_terms', 1, clean_query) unless clean_query.length < 3
  $redis.incr('searches')

  content_type :json
  status 200
  results.to_json
end

private

def format_number(num)
  # Is this seriously the only way?
  num.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
end
