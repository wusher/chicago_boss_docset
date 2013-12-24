require 'nokogiri'
require 'uri'
require 'open-uri'
require 'json'
require 'pry'
require 'erb'
require 'sqlite3'

task :default  => [:init, :download, :populate, :prepare]

DOCSET_NAME = "ChicagoBoss"
DOC_FOLDER  = "#{DOCSET_NAME}.docset/Contents/Resources/Documents/"
INFO_FOLDER = "#{DOCSET_NAME}.docset/Contents"
BASE_URL    = "http://www.chicagoboss.org/"
SQL_DB      = "#{DOCSET_NAME}.docset/Contents/Resources/docset.dsidx"
LOGO_PATH   = "#{DOCSET_NAME}.docset/icon.png"

DOCUMENTS = Set.new

task :clean do
  `rm -rf #{DOCSET_NAME + ".docset"}`
  `rm     #{DOCSET_NAME + ".docset.tar.gz"}`
end

task :init => [:clean] do
  FileUtils.mkdir_p DOC_FOLDER
  template "templates/info.plist.erb", File.join(INFO_FOLDER, "Info.plist"),
           bundle_identifier: DOCSET_NAME,
           bundle_name: DOCSET_NAME,
           platform_family: DOCSET_NAME,
           index_path: "api.html"
  FileUtils.cp("logo16x16.png", LOGO_PATH)
  create_db
end

task :download => [:init] do
  root = BASE_URL + "api.html"
  doc = Nokogiri::HTML(open(root))
  # download css
  download_paths doc.search("link")

  download root, "api.html"
  # download sections
  download_paths doc.search(".subnav a")
end


task :populate do

  record_search "API Documentation", "Guide", all_documents.find { |x| x !~ /-/ }
  all_documents.each do |path|
    full_path = File.join(DOC_FOLDER, path)
    doc = Nokogiri::HTML(File.open(full_path))
    parent = doc.search(".subnav strong").first
    record_search parent.text, "Guide", path if parent

    sections = doc.search("a").select { |x| x.attr("href") =~ /^#/ }
    sections.each do |section|
      key = section.attr("href").sub("#", "")
      anchor = doc.search("a").select{ |x| x.attr("name") == key}.first
      apple_anchor = anchor.dup
      apple_anchor.set_attribute "name", "//apple_ref/Section/#{section.text}"
      apple_anchor.set_attribute "class", "dashAnchor"
      anchor.add_next_sibling(apple_anchor)
      record_search  parent.text + " => " + section.text, "Section", path + "#//apple_ref/Section/#{section.text}"
    end

    cust_sections = doc.search("h2")
    cust_sections.each do |section|
      apple_anchor = section.dup
      apple_anchor.name = "a"
      apple_anchor.content = ""
      apple_anchor.set_attribute "name", "//apple_ref/Section/#{section.text}"
      apple_anchor.set_attribute "class", "dashAnchor"
      section.add_previous_sibling(apple_anchor)
      record_search  parent.text + " => " + section.text, "Section", path + "#//apple_ref/Section/#{section.text}"
    end

    File.write full_path, doc.to_s
  end
end

task :prepare do
  `tar -zcf #{DOCSET_NAME}.docset.tar.gz #{DOCSET_NAME}.docset `
end


def download_paths(nodes)
  nodes.each do |node|
    name = node.attribute("href").value
    url = BASE_URL + name
    download  url, name
  end
end

def download(url, path)
  full_path = File.join(DOC_FOLDER, path)

  File.open(full_path, "w") do |file|
    open(url, "r") do |contents|
      file.write(contents.read)
      DOCUMENTS << full_path
    end
  end
end


def template(source, destination, payload)
  context = OpenStruct.new(payload)
  contents = File.read(source)
  generator = ERB.new(contents)
  output = generator.result(context.instance_eval { binding })
  File.write destination, output
end

def record_search(name, type, path)
  query = "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{name}', '#{type}', '#{path}');"
  sql_db.execute query
end

def create_db
  db = SQLite3::Database.new(SQL_DB)
  db.execute "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);"
  db.execute "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);"
end

def sql_db
  @db ||= SQLite3::Database.new(SQL_DB)
end

def all_documents
  unless @all_documents
    @all_documents = []
    @all_documents = Dir.entries(DOC_FOLDER).select { |x| /html/ =~ x }
    @all_documents.sort!
  end
  @all_documents
end

