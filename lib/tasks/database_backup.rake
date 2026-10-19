namespace :db do
  desc "Upload a backup of the SQLite primary database to Cloudflare R2 now"
  task backup_to_r2: :environment do
    abort "Set #{DatabaseBackup::REQUIRED_ENV.join(', ')} first." unless DatabaseBackup.configured?

    puts "Uploaded #{DatabaseBackup.new.call}"
  end
end
