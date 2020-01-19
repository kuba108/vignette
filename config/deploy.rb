require 'mina/rails'
require 'mina/git'
require 'mina/rbenv'
require 'mina/supervisord'
#require 'mina/delayed_job'

require 'dotenv/tasks'
require 'yaml'
require 'erb'

# Basic settings:
#   domain       - The hostname to SSH to.
#   deploy_to    - Path to deploy into.
#   repository   - Git repo to clone from. (needed by mina/git)
#   branch       - Branch name to deploy. (needed by mina/git)

set :application_name, 'vignette'
set :domain, '139.59.212.53'
set :repository, 'git@github.com:kuba108/vignette.git'
set :branch, (ENV['BRANCH'] ? ENV['BRANCH'] : 'master')
set :user, 'deploy'
set :force_asset_precompile, true

#set :force_migrate, true

if ENV['ENV'] == 'production'
  set :deploy_env, 'production'
  set :deploy_to, "/home/www/production/apps/#{fetch(:application_name)}"
  set :application_supervisor_file, "#{fetch(:application_name)}_puma"
  #set :dj_supervisor_file, "mpt_dj"
else
  set :deploy_env, 'test'
  set :deploy_to, "/home/www/test/apps/#{fetch(:application_name)}"
  set :application_supervisor_file, "#{fetch(:application_name)}_test_puma"
  #set :dj_supervisor_file, "mpt_test_dj"
end

set :supervisorctl_cmd, -> { "sudo /usr/bin/supervisorctl -c /etc/supervisor/supervisord.conf" }

set :database_path, "config/database.yml"
set :remote_backup_path, "../shared/dumps"
set :local_backup_path, -> { 'db/dumps' || 'tmp' }
set :backup_file, -> { %{#{fetch(:repository).split('/').last.split('.').first}-#{fetch(:rails_env)}-#{Date.today}.sql} }

# Optional settings:
#   set :user, 'foobar'          # Username in the server to SSH to.
#   set :port, '30000'           # SSH port number.
set :forward_agent, true     # SSH forward_agent.

# shared dirs and files will be symlinked into the app-folder by the 'deploy:link_shared_paths' step.
# set :shared_dirs, fetch(:shared_dirs, []).push('somedir')
# set :shared_files, fetch(:shared_files, []).push('config/database.yml', 'config/secrets.yml')
set :shared_dirs, fetch(:shared_dirs, []).push('log', 'tmp', 'private', 'public/assets', 'storage')
# This task is the environment that is loaded for all remote run commands, such as
# `mina deploy` or `mina rake`.
task :environment do
  # If you're using rbenv, use this to load the rbenv environment.
  # Be sure to commit your .ruby-version or .rbenv-version to your repository.
  invoke :'rbenv:load'

  # For those using RVM, use this to load an RVM version@gemset.
  # invoke :'rvm:use', 'ruby-1.9.3-p125@default'
end

# Put any custom commands you need to run at setup
# All paths in `shared_dirs` and `shared_paths` will be created on their own.
task :setup do
  command %[mkdir -p "#{fetch(:shared_path)}/log"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/log"]

  command %[mkdir -p "#{fetch(:shared_path)}/tmp/pids"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/tmp/pids"]

  command %[mkdir -p "#{fetch(:shared_path)}/tmp/sockets"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/tmp/sockets"]

  command %[mkdir -p "#{fetch(:shared_path)}/private"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/private"]

  command %[mkdir -p "#{fetch(:shared_path)}/public/assets"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/public/assets"]

  command %[mkdir -p "#{fetch(:shared_path)}/config"]
  command %[chmod g+rx,u+rwx "#{fetch(:shared_path)}/config"]

  command %[touch "#{fetch(:deploy_to)}/.rbenv-vars"]
  comment  "Be sure to edit '#{fetch(:deploy_to)}/.rbenv-vars' for environment variables."
  comment  "Also create '#{fetch(:deploy_to)}/shared/config/puma.rb' from repo's puma.rb"

  if fetch(:repository)
    repo_host = fetch(:repository).split(%r{@|://}).last.split(%r{:|\/}).first
    repo_port = /:([0-9]+)/.match(fetch(:repository)) && /:([0-9]+)/.match(fetch(:repository))[1] || '22'

    command %[
      if ! ssh-keygen -H  -F #{repo_host} &>/dev/null; then
        ssh-keyscan -t rsa -p #{repo_port} -H #{repo_host} >> ~/.ssh/known_hosts
      fi
    ]
  end
end

desc "Deploys the current version to the server."
task :deploy do
  # uncomment this line to make sure you pushed your local branch to the remote origin
  # invoke :'git:ensure_pushed'
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'

    on :launch do
      invoke :'phased_restart'
      #invoke :'delayed_job:restart'
    end
  end

  # you can use `run :local` to run tasks on local machine before of after the deploy scripts
  # run(:local){ say 'done' }
end

desc "Starts an interactive rails console."
task :c => :environment do
  invoke :'console'
end

desc "Show application log file"
task :log do
  command echo_cmd %[cd "#{fetch(:deploy_to)}" && tail -f shared/log/production.log]
end

## APPLICATION
desc "Stops application"
task :stop => :environment do
  invoke :'supervisord:stop', fetch(:application_supervisor_file)
end

desc "Starts application"
task :start => :environment do
  invoke :'supervisord:start', fetch(:application_supervisor_file)
end

desc "Phased retarts application"
task :phased_restart => :environment do
  invoke :'supervisord:signal:or_start', fetch(:application_supervisor_file), "SIGUSR1"
end

desc "Status of application"
task :status => :environment do
  invoke :'supervisord:status', fetch(:application_supervisor_file)
end

## DJ
desc "Stops DJ"
task :dj_stop => :environment do
  invoke :'supervisord:stop', fetch(:dj_supervisor_file)
end

desc "Starts DJ"
task :dj_start => :environment do
  invoke :'supervisord:start', fetch(:dj_supervisor_file)
end

desc "Restarts DJ"
task :dj_restart => :environment do
  invoke :'supervisord:restart:or_start', fetch(:dj_supervisor_file)
end

desc "Status of DJ"
task :dj_status => :environment do
  invoke :'supervisord:status', fetch(:dj_supervisor_file)
end

# desc "Recreate database"
# task :recreate_db do
#   deploy do
#     invoke :'git:clone'
#     invoke :'deploy:link_shared_paths'
#     invoke :'bundle:install'
#     invoke :'rails:db_migrate'
#     # comment %{Migrating database}
#     # command %{#{fetch(:rake)} db:migrate}
#   end
# end

## REMOTE DB SYNC
namespace :sync do
  task :make_remote_dump => :environment do
    set :pg_dump_bin, "/usr/pgsql-9.6/bin/pg_dump"
    set :dump_path, "#{fetch(:shared_path)}/dumps"
    set :dump_name, "#{fetch(:application_name)}_#{fetch(:deploy_env)}-#{Time.now.strftime('%Y-%m-%d')}.dump"
    set :dump_file_path, "#{fetch(:dump_path)}/#{fetch(:dump_name)}"
    set :local_dump_name, 'db/dumps/production.dump'

    run :remote do
      command %[cd "#{fetch(:deploy_to)}"]
      command %[eval "$(rbenv vars)"]
      comment "Making remote dump..."
      command "PGPASSWORD=$DB_PASS #{fetch(:pg_dump_bin)} -U $DB_USER -h $DB_HOST -F c --no-owner --no-acl -f #{fetch(:dump_file_path)} $DB_NAME"
      comment "GZipping on remote server..."
      command "gzip -f #{fetch(:dump_file_path)}"
    end
  end

  task load_local_db_config: :dotenv do
    yaml_file = ERB.new File.new('config/database.yml').read
    set :devel_conf, YAML.load(yaml_file.result(binding))["development"]
  end

  task :db => :environment do
    invoke :'sync:make_remote_dump'
    invoke :'sync:load_local_db_config'

    run :local do
      comment "Copying dump to local..."
      command %{rsync -rv --progress -e ssh #{fetch(:user)}@#{fetch(:domain)}:#{fetch(:dump_file_path)}.gz #{fetch(:local_dump_name)}.gz}
      comment "UnZipping dump on local..."
      command %{gunzip -f #{fetch(:local_dump_name)}.gz}
      comment "Dropping local database..."
      command %{dropdb #{fetch(:devel_conf)['database']}}
      comment "Creating local database..."
      command %{createdb #{fetch(:devel_conf)['database']}}
      comment "Restoring local database..."
      command %{pg_restore -d #{fetch(:devel_conf)['database']} --no-owner --role=#{fetch(:devel_conf)['username']} #{fetch(:local_dump_name)}}
      comment "Cleanup!"
      command %{rm #{fetch(:local_dump_name)}}
      comment "Rails 5 updating internal metadata."
      command %{psql -d #{fetch(:devel_conf)['database']} -U #{fetch(:devel_conf)['username']} -c "UPDATE ar_internal_metadata SET value = 'development' WHERE key = 'environment' AND value = 'production';"}
    end
  end
end

# For help in making your deploy script, see the Mina documentation:
#
#  - https://github.com/mina-deploy/mina/tree/master/docs
