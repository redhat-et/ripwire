module App
  module Services
    extend ActiveSupport::Autoload

    autoload :Mailer
    eager_autoload do
      autoload :Job
    end
    autoload_under "impl" do
      autoload :Worker
    end
    autoload :Legacy, "lib/legacy_impl"
  end
end
