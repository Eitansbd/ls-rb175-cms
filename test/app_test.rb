require 'fileutils'

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms.rb"

class AppTest < Minitest::Test
	include Rack::Test::Methods

	def app
		Sinatra::Application
	end

	def setup
		FileUtils.mkdir_p(data_path)

		bcyrpt_password = BCrypt::Password.create("Secret").to_s
		users = {"Admin" => bcyrpt_password}
		File.write(users_path, users.to_yaml)
	end

	def teardown
		FileUtils.rm_rf(data_path)
		File.delete(users_path)
	end

	def create_document(name, content="")
		File.open(File.join(data_path, name), "w") do |file|
			file.write(content)
		end
	end

	def session
		last_request.env["rack.session"]
	end

	def admin_session
		{ "rack.session" => {username: "Admin"}}
	end

	def test_index
		create_document("about.txt")
		create_document("history.txt")

		get "/"
		
		assert_equal 200, last_response.status
		assert_includes last_response.body, "about.txt"
		assert_includes last_response.body, "history.txt"
	end

	def test_viewing_text_document
		create_document("changes.txt", "Hello World")

		get "/changes.txt"

		assert_equal 200, last_response.status
		assert_equal "text/plain", last_response["Content-Type"]
		assert_includes last_response.body, "Hello World"
	end

	def test_viewing_markdown
		create_document("markdownfile.md")

		get "/markdownfile.md"

		assert_equal 200, last_response.status
		assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
	end

	def test_not_a_file_error
		get "/notafile.txt"

		assert_equal 302, last_response.status
		assert_equal "notafile.txt does not exist.", session[:error]

		get last_response["Location"]

		assert_equal 200, last_response.status
		assert_includes last_response.body, "notafile.txt does not exist"

		get "/"
		refute_includes last_response.body, "notafile.txt does not exist"
	end

	def test_editing_document
	 	create_document("changes.txt")

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
  	create_document("changes.txt")

  	get "/changes.txt/edit"

  	assert_equal 302, last_response.status
  	assert_equal "You must be signed in to do that", session[:error]
  end

  def test_updating_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated", session[:success]

    get last_response["Location"]

    assert_includes last_response.body, "changes.txt has been updated"

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt", content: "new content"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:error]
  end

  def test_new_document_page
  	get "/newfile", {}, admin_session

  	assert_equal 200, last_response.status
  	assert_includes last_response.body, "Add a new document:" 
  end

  def test_new_document_page_signed_out
  	get "/newfile"

  	assert_equal 302, last_response.status
  	assert_equal "You must be signed in to do that", session[:error]
  end

  def test_create_document
  	post "/createfile", {filename: "doc_name.txt"}, admin_session

  	assert_equal 302, last_response.status
  	assert_equal "doc_name.txt was created", session[:success]

  	get last_response["Location"]

  	assert_includes last_response.body, "doc_name.txt"
  	assert_equal 200, last_response.status

  	get "/"
  	assert_includes last_response.body, "doc_name.txt"
  end

  def test_create_documnet_signed_out
  	post "/createfile", {filename: "doc_name.txt"}

  	assert_equal 302, last_response.status
  	assert_equal "You must be signed in to do that", session[:error]
  end

  def test_create_document_no_name_error
  	post "/createfile", {filename: "  "}, admin_session

  	assert_equal 422, last_response.status


  	assert_includes last_response.body, "Add a new document:"
  	assert_includes last_response.body, "A name is required."
  end

  def test_create_document_invalid_extension_error
  	post "/createfile", {filename: "test"}, admin_session

  	assert_equal 422, last_response.status

  	assert_includes last_response.body, "Invalid extension"
  	assert_includes	last_response.body, "Add a new document"
  end

  def test_duplicate_document
  	create_document("test.txt")

  	post "/test.txt/duplicate", {}, admin_session

  	assert_equal 302, last_response.status
  	assert_equal "test.txt has been duplicated", session[:success]

  	get last_response["Location"]
  	
  	assert_equal 200, last_response.status
  	assert_includes last_response.body, "copy_of_test.txt"
  end

  def test_deleting_document
  	create_document("test.txt")

  	post "/test.txt/destroy", {}, admin_session

  	assert_equal 302, last_response.status
  	assert_equal "test.txt has been deleted", session[:success]

  	get last_response["Location"]
  	assert_includes last_response.body, "test.txt has been deleted"

  	get "/"
  	refute_includes last_response.body, "test.txt"
  end

  def test_deleting_document_signed_out
  	create_document("test.txt")

  	post "/test.txt/destroy"

  	assert_equal 302, last_response.status
  	assert_equal "You must be signed in to do that", session[:error]
  end

  def test_sign_in_button
  	get "/"

  	assert_equal 200, last_response.status
  	assert_includes last_response.body, "Sign in"
  end

  def test_sign_out_button
  	get "/", {}, {"rack.session" => { username: "Admin" }}

  	assert_equal 200, last_response.status
  	assert_includes last_response.body, "Signed in as"
  end

  def test_signin
  	post "/users/login", {username: "admin", password: "Secret"}

  	assert_equal 302, last_response.status
  	assert_equal "Welcome!", session[:success]
  	assert_equal "admin", session[:username]

  	get last_response["Location"]
  	assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_bad_credentials
  	post "/users/login", {username: "Invalid", password:"Invalid"}

  	assert_equal 422, last_response.status
  	assert_includes last_response.body, "Invalid credential"

  	assert_nil session[:username]
  end

  def test_signout
  	get "/", {}, {"rack.session" => {username: "Admin"} }
  	assert_includes last_response.body, "Signed in as Admin"

  	post "/users/logout"
  	assert_equal "You have been signed out", session[:success]

  	get last_response["Location"]
  	assert_nil session[:username]
  	assert_includes last_response.body, "Sign in"
  end

  def test_create_new_user_page
  	get "/users/new"

  	assert_equal 200, last_response.status
  	assert_includes last_response.body, '<label for="username">Username: </label>'
  end

  def test_create_new_user
  	post "/users/new", {username: "test", password: "test"}

  	assert_equal 302, last_response.status

  	get last_response["Location"]
  	assert_equal 200, last_response.status
  	assert_includes last_response.body, "Signed in as test"

  	post "/users/logout"
  	post "/users/login", {username: "test", password: "test"}
  	
  	get last_response["Location"]
  	assert_includes last_response.body, "Signed in as test"
  end
end