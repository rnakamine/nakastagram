require 'sinatra/base'
require 'sinatra/reloader'
require 'mysql2'
require 'active_record'
require 'active_support/all'
require 'rack-flash'
require 'pry'

class Nakastagram < Sinatra::Base
  Time.zone_default = Time.find_zone! 'Tokyo'
  ActiveRecord::Base.default_timezone = :local

  ActiveRecord::Base.configurations = YAML.load_file('database.yml')
  ActiveRecord::Base.establish_connection(:development)

  use Rack::Flash
  set :public, File.dirname(__FILE__) + '/public'
  enable :sessions

  helpers do
    def login?
      session[:user_id].present?
    end

    def set_current_user
      @current_user = User.find(session[:user_id]) if login?
    end

    def authenticate_user
      unless login?
        flash[:notice] = 'ログインが必要です'
        redirect to('/login')
      end
    end
  end

  before do
    set_current_user
  end

  get '/' do
    authenticate_user

    @title = 'Nakastagram'
    @posts = Post.all.order(created_at: :desc)
    erb :index
  end

  get '/new' do
    authenticate_user
    @post = Post.new
    erb :new
  end

  post '/create' do
    if params[:image] != nil
      filename = "/image/#{params[:image][:filename]}"
      image = params[:image][:tempfile]
    end

    @post = Post.new(
        content: params[:content],
        image_path: filename,
        user_id: @current_user.id
    )
    if @post.save
      File.open("./public#{filename}", 'wb') do |f|
        f.write(image.read)
      end

      flash[:notice] = '投稿しました'
      redirect to('/')
    else
      erb :new
    end
  end

  get '/post/:id' do
    authenticate_user
    @post = Post.find(params[:id])
    erb :post
  end

  get '/edit/:id' do
    authenticate_user
    @post = Post.find(params[:id])
    erb :edit
  end

  post '/edit/:id' do
    @post = Post.find(params[:id])

    if @post.update(content: params[:content])
      flash[:notice] = '編集しました'
      redirect to('/')
    else
      erb :edit
    end
  end

  post '/destroy/:id' do
    Post.find(params[:id]).destroy
    flash[:notice] = '投稿を削除しました'
    redirect to('/')
  end

  get '/signup' do
    @user = User.new
    erb :signup
  end

  post '/user_create' do
    @user = User.new(name: params[:name], password: params[:password])

    if @user.save
      session[:user_id] = @user.id
      flash[:notice] = '登録しました'
      redirect to('/')
    else
      erb :signup
    end
  end

  get '/login' do
    erb :login
  end

  post '/login' do
    @user = User.find_by(name: params[:name], password: params[:password])

    if @user
      session[:user_id] = @user.id
      flash[:notice] = 'ログインしました'
      redirect to('/')
    else
      @error_message = 'ユーザー名またはパスワードが間違っています。'
      @name = params[:name]
      @password = params[:password]
      erb :login
    end
  end

  get '/logout' do
    session[:user_id] = nil
    flash[:notice] = 'ログアウトしました'
    redirect to('/login')
  end

  get '/users' do
    authenticate_user
    @users = User.all
    erb :users
  end

  get '/@:name' do
    authenticate_user
    @user = User.find_by(name: params[:name])
    erb :user_show
  end
end

class Post < ActiveRecord::Base
  validates :content, presence: true
  validates :image_path, presence: true

  def user
    User.find_by(id: self.user_id)
  end
end

class User < ActiveRecord::Base
  validates :name, presence: true, uniqueness: true
  validates :password, presence: true

  def posts
    Post.where(user_id: self.id)
  end
end