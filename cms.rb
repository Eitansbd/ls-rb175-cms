require 'pry'
require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'sercet'
end

def data_path 
	if ENV['RACK_ENV'] == "test"
		File.expand_path("../test/data", __FILE__)
	else
		File.expand_path("../data", __FILE__)
	end
end

def users_path
	if (ENV['RACK_ENV'] == "test")
		File.expand_path("../test/users.yml", __FILE__)
	else
		File.expand_path("../users.yml", __FILE__)
	end
end

def load_user_credentials
	YAML.load_file(users_path)
end

def valid_credentials?(username, password)
	credentials = load_user_credentials

	if credentials.key?(username)
		bcyrpt_password = BCrypt::Password.new(credentials[username])
		bcyrpt_password == password
	else
		false
	end
end

def logged_in?
	session[:username]
end

def redirect_sign_in_required
	if !logged_in?
		session[:error] = "You must be signed in to do that"
		redirect "/"
	end
end

get '/' do 
	pattern = File.join(data_path, "*")
	@files = Dir.glob(pattern).map { |path| File.basename(path) }
	erb :all_files
end

# renders create document page
get "/newfile" do 
	redirect_sign_in_required
	
	erb :new_file
end

def invalid_extension?(file_name)
	!['.md', '.txt', '.jpg', '.png'].include?(File.extname(file_name))
end

# creates a file
post "/createfile" do 
	redirect_sign_in_required

	file_name = params[:filename]

	if file_name.strip.empty?
		session[:error] = "A name is required."
		status 422

		erb :new_file
	elsif invalid_extension?(file_name)
		session[:error] = "Invalid extension"
		status 422

		erb :new_file

	else

		File.write File.join(data_path, file_name), ""
		session[:success] = "#{file_name} was created"
		redirect "/"
	end
end

def render_markdown(text)
	markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
	markdown.render(text)
end

def load_file_content(file_path)
	text = File.read(file_path)
	
	case File.extname(file_path)
	when ".md"
		erb render_markdown(text)
	when ".txt"	
		response.headers['Content-Type'] = "text/plain"
		text
	else
		file_name = File.basename(file_path)
		session[:error] = file_name + " does not exist"
		redirect "/"
	end
end

# renders content of file
get '/:file_name' do |file_name|
	file_path = File.join(data_path,file_name)

	if !File.exist? file_path 
		session[:error] = file_name + " does not exist."
		redirect '/'
	end
	
	load_file_content(file_path)
end

# renders edit file page 
get "/:file_name/edit" do |file_name|
	redirect_sign_in_required

	@file_name = file_name
	file_path = File.join(data_path, file_name)

	if !File.exist? file_path 
		session[:error] = file_name + " does not exist."
		redirect '/'
	end

	@content = File.read(file_path)
	erb :edit_file
end

# edits the content of a file
post "/:file_name" do |file_name|
	redirect_sign_in_required
	file_path = File.join(data_path, file_name)
	
	File.write(file_path, params[:content])
		
	session[:success] = file_name + " has been updated"
	redirect '/'
end

# deletes a file
post "/:file_name/destroy" do |file_name|
	redirect_sign_in_required

	file_path = File.join(data_path, file_name)

	File.delete(file_path)
	session[:success] = "#{file_name} has been deleted"

	redirect "/"
end

# duplicated a file
post "/:file_name/duplicate" do |file_name|
	redirect_sign_in_required

	file_path = File.join(data_path, file_name)
	content = File.read(file_path)

	new_file_name = "copy_of_" + file_name
	new_file_path = File.join(data_path, new_file_name)
	
	File.write new_file_path, content

	session[:success] = file_name + " has been duplicated"
	redirect "/"
end

get "/users/new" do
	erb :new_user
end

def create_user(username, password)
	credentials = load_user_credentials
	hashed_password = BCrypt::Password.create(password)
	credentials[username] = hashed_password.to_s

	File.write(users_path, credentials.to_yaml)
end

def username_exists?(username)
	credentials = load_user_credentials
	credentials.key?(username)
end

post "/users/new" do 
	username = params[:username]
	password = params[:password]

	if username_exists?(username)
		status 422
		session[:error] = username + " already has an account"
		erb :new_user
	else
		create_user(username, password)
		session[:username] = username
		redirect "/"
	end
end

get "/users/login" do 
	erb :login
end

post "/users/login" do
	credentials = load_user_credentials
	username = params[:username].downcase
	password = params[:password]

	if valid_credentials?(username, password)
		session[:username] = username
		session[:success] = "Welcome!"
		redirect "/"
	else
		status 422
		session[:error] = "Invalid credentials"
		erb :login
	end
end

post "/users/logout" do 
	session.delete(:username)
	session[:success] = "You have been signed out"
	redirect "/"	
end