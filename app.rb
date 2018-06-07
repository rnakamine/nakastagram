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
    def set_current_user
      @current_user = User.find(session[:user_id]) if session[:user_id]
    end

    def authenticate_user
      unless session[:user_id]
        flash[:notice] = 'ログインが必要です'
        redirect to('/login_form')
      end
    end

    def forbid_login_user
      if @current_user
        flash[:notice] = 'すでにログインしています'
        redirect to('/')
      end
    end

    def ensure_correct_post
      post = Post.find(params[:id])
      if @current_user.id != post.user_id
        flash[:notice] = '権限がありません'
        redirect to('/')
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
    authenticate_user
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
    ensure_correct_post
    @post = Post.find(params[:id])
    erb :edit
  end

  post '/update/:id' do
    ensure_correct_post
    @post = Post.find(params[:id])

    if @post.update(content: params[:content])
      flash[:notice] = '編集しました'
      redirect to('/')
    else
      erb :edit
    end
  end

  post '/destroy/:id' do
    ensure_correct_post
    Post.find(params[:id]).destroy
    flash[:notice] = '投稿を削除しました'
    redirect to('/')
  end

  get '/signup' do
    forbid_login_user
    @user = User.new
    erb :signup
  end

  post '/user_create' do
    @user = User.create(name: params[:name], password: params[:password])

    if @user.save
      session[:user_id] = @user.id
      flash[:notice] = '登録しました'
      redirect to('/')
    else
      erb :signup
    end
  end

  get '/login_form' do
    forbid_login_user
    erb :login
  end

  post '/login' do
    forbid_login_user
    @user = User.find_by(name: params[:name])

    if @user && @user.authenticate(params[:password])
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
    redirect to('/login_form')
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

  get '/user_edit/@:name' do
    @user = User.find_by(name: params[:name])
    erb :user_edit
  end

  post '/like_create/:id' do
    Like.create(user_id: @current_user.id, post_id: params[:id])
    redirect to('/')
  end

  post '/like_destroy/:id' do
    Like.find_by(user_id: @current_user.id, post_id: params[:id]).destroy
    redirect to('/')
  end

  post '/comment_create/:post_id/:user_id' do
    @comment = Comment.new(
        post_id: params[:post_id],
        user_id: params[:user_id],
        comment: params[:comment]
    )
    @comment.save
    redirect to('/')
  end

end

class Post < ActiveRecord::Base
  validates :content, presence: true
  validates :image_path, presence: true

  belongs_to :user
  has_many :comment
end

class User < ActiveRecord::Base
  has_secure_password

  validates :name, presence: true, uniqueness: true

  has_many :post
  has_many :comment
end

class Like < ActiveRecord::Base
  validates :user_id, presence: true
  validates :post_id, presence: true
end

class Comment < ActiveRecord::Base
  validates :user_id, presence: true
  validates :post_id, presence: true
  validates :comment, presence: true

  belongs_to :user
  belongs_to :post
end