require 'sinatra'
require 'sinatra/base'
require 'sinatra/reloader' if development?
require 'mysql2'
require 'active_record'
require 'active_support/all'
require 'rack-flash'
require 'pry' if development?

class Nakastagram < Sinatra::Base
  Time.zone_default = Time.find_zone! 'Tokyo'
  ActiveRecord::Base.default_timezone = :local

  ActiveRecord::Base.configurations = YAML.load_file('database.yml')
  ActiveRecord::Base.establish_connection(:development)

  use Rack::Flash
  set :public_folder, File.dirname(__FILE__) + '/public'
  enable :sessions

  helpers do
    def set_current_user
      @current_user = User.find(session[:user_id]) if session[:user_id]
    end

    def authenticate_user
      unless session[:user_id]
        flash[:error] = 'ログインが必要です'
        redirect to('/')
      end
    end

    def forbid_login_user
      if @current_user
        flash[:error] = 'すでにログインしています'
        redirect to('/')
      end
    end

    def ensure_correct_post
      post = Post.find(params[:id])
      if @current_user.id != post.user_id
        flash[:error] = '権限がありません'
        redirect to('/')
      end
    end
  end

  before do
    set_current_user
  end

  get '/' do
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

  get '/post_:id' do
    authenticate_user
    @post = Post.find(params[:id])
    erb :post
  end

  get '/edit_:id' do
    authenticate_user
    ensure_correct_post
    @post = Post.find(params[:id])
    erb :edit
  end

  post '/update_:id' do
    ensure_correct_post
    @post = Post.find(params[:id])

    if @post.update(content: params[:content])
      flash[:notice] = '編集しました'
      redirect to('/')
    else
      erb :edit
    end
  end

  post '/destroy' do
    ensure_correct_post
    Post.find(params[:id]).destroy
  end

  get '/signup' do
    forbid_login_user
    @user = User.new
    erb :signup
  end

  post '/user_create' do
    if params[:user_image] != nil
      filename = "/image/user_image/#{params[:user_image][:filename]}"
      image = params[:user_image][:tempfile]
    else
      filename = "/image/user_image/default-user-image.png"
    end

    @user = User.new(
        name: params[:name],
        password: params[:password],
        user_image: filename
    )

    if @user.save
      if image
        File.open("./public#{filename}", 'wb') do |f|
          f.write(image.read)
        end
      end

      session[:user_id] = @user.id
      flash[:notice] = '気になるユーザーをフォローしましょう！'
      redirect to('/users')
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
    redirect to('/')
  end

  get '/users' do
    authenticate_user
    @users = User.all
    erb :users
  end

  get '/@:name' do
    authenticate_user
    @user = User.find_by(name: params[:name])
    erb :profile
  end

  get '/user_edit_@:name' do
    @user = User.find_by(name: params[:name])
    erb :user_edit
  end

  post '/user_update_:name' do
    if params[:user_edit_image] != nil
      filename = "/image/user_image/#{params[:user_edit_image][:filename]}"
      image = params[:user_edit_image][:tempfile]
    end


    @user = User.find_by(name: params[:name])

    if image
      File.open("./public#{filename}", 'wb') do |f|
        f.write(image.read)
      end

      @user.update(name: params[:user_edit_name], user_image: filename)
      flash[:notice] = 'ユーザーを編集しました'
      redirect to("/@#{@user.name}")
    else
      @user.update(name: params[:user_edit_name])
      flash[:notice] = 'ユーザーを編集しました'
      redirect to("/@#{@user.name}")
    end
  end

  post '/like_create' do
    authenticate_user
  end

  post '/like_create/:id' do
    Like.create(user_id: @current_user.id, post_id: params[:id])
    flash[:notice] = '投稿にいいね！しました'
    redirect to('/')
  end

  post '/like_destroy/:id' do
    Like.find_by(user_id: @current_user.id, post_id: params[:id]).destroy
    flash[:notice] = 'いいね！を取り消しました'
    redirect to('/')
  end

  post '/comment_create' do
    authenticate_user
  end

  post '/comment_create/:post_id/:user_id' do
    @comment = Comment.new(
        post_id: params[:post_id],
        user_id: params[:user_id],
        comment: params[:comment]
    )
    if @comment.save
      flash[:notice] = '投稿にコメントしました'
      redirect to('/')
    end
  end

  post '/follow/:user_id' do
    Rerationship.create(follower_id: @current_user.id, followed_id: params[:user_id])
    redirect to('/users')
  end

  post '/unfollow/:user_id' do
    Rerationship.find_by(follower_id: @current_user.id, followed_id: params[:user_id]).destroy
    redirect to('/users')
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
  has_many :rerationship
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

class Rerationship < ActiveRecord::Base
  validates :follower_id, presence: true
  validates :followed_id, presence: true

  has_many :user
end

