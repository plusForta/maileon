require 'mail/check_delivery_params'

module Mail

  # Sending email from maileon via action_mailer's deliver-method
  # Integrates with action_mailer via railtie for rails 3/4 (see lib/maileon/railtie.rb)
  # configuration could be done on application initializers
  #   config.action_mailer.delivery_method              = :maileon_transaction
  #   config.action_mailer.maileon_transaction_settings = {
  #     :api_key => "xxxxxx-yyy-xxx-yyyyyy"
  #   }
  class MaileonTransactionDelivery
    include Mail::CheckDeliveryParams

    HEADER_TYPE_KEY = :"X-Maileon-TransactionType"
    HEADER_VARS_KEY = :"X-Maileon-Variables"

    attr_accessor :settings
    attr_reader   :api

    # emtpy initializer for now
    def initialize settings
      # do something with config
      @settings ||= {}
      @settings.merge!(settings)

      # api object
      @api = Maileon::API.new(settings[:api_key], true)
    end

    def deliver!(mail)
      # implement maileon send
      check_delivery_params(mail)

      # query api for type
      transaction_type = check_maileon_transaction_params(mail)

      # query api for variables
      # generate variable mapping
      variables = check_maileon_variables(transaction_type, mail)

      # send type api with params
      api.create_transaction(
        transaction_type["id"].to_i,
        variables.merge(
          {
            "import" => {
              "contact" => {
                "email" => mail["to"].value,
                # TODO resolve hardcoded user permission here for dynamic version
                "permission" => 5
              }
            }
          }
        )
      )
      # mail
      mail
    end

    private
    def check_maileon_transaction_params mail
      check_api_key
      check_transaction_type mail
    end

    def check_api_key
      # TODO check api if key works for create and read
    end

    def check_transaction_type mail
      avail_transactions = api.get_all_transaction_types

      finder = lambda do |entry|
        entry["name"] == "#{mail[HEADER_TYPE_KEY].field}"
      end

      raise (runtime_error "unable to find transaction") unless avail_transactions.find(&finder)
      avail_transactions.find(&finder)
    end

    def check_maileon_variables(transaction_type, mail)
      begin
        variables = JSON.parse mail[HEADER_VARS_KEY].value
      rescue
        raise (runtime_error "unable to load/parse :maileon_variables for mail")
      end
      errors = transaction_type["attributes"]["attribute"].inject([]) do |errors, entry|
        errors << entry["name"] unless variables.keys.include?(entry["name"])
        errors
      end
      ActionMailer::Base.logger.debug "check_maileon_variables #{transaction_type["attributes"]["attribute"]}"
      raise (runtime_error "missing variable/s #{errors}") unless errors.empty?
      errors.empty? && variables
    end

    def runtime_error msg
       RuntimeError.new "maileon action_mailer integration :: #{msg}"
    end

  end
end
