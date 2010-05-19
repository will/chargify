module Chargify
  class UnexpectedResponseError < RuntimeError;end

  def self.custom_parser
    proc do |data|  
      begin
        Crack::JSON.parse(data)
      rescue => e
        error_msg = "Crack could not parse JSON. It said: #{e.message}. Chargify's raw response: #{data}"
        raise UnexpectedResponseError, error_msg
      end
    end
  end
    
  class Client
    include HTTParty
    format :json
    parser Chargify::custom_parser
    headers 'Content-Type' => 'application/json' 
    
    attr_reader :api_key, :subdomain
    
    # Your API key can be generated on the settings screen.
    def initialize(api_key, subdomain)
      @api_key = api_key
      @subdomain = subdomain
      
      self.class.base_uri "https://#{@subdomain}.chargify.com"
      self.class.basic_auth @api_key, 'x'
      
    end
    
    # options: page
    def list_customers(options={})
      customers = get("/customers.json", :query => options)
      customers.map{|c| Hashie::Mash.new c['customer']}
    end

    def customer_by_chargify_id(chargify_id)
      Hashie::Mash.new(get("/customers/#{chargify_id}.json")).customer
    end
    alias :customer :customer_by_chargify_id

    def customer_by_reference(reference)
      Hashie::Mash.new(get("/customers/lookup.json?reference=#{reference}")).customer
    end
    
    #
    # * first_name (Required)
    # * last_name (Required)
    # * email (Required)
    # * organization (Optional) Company/Organization name
    # * reference (Optional, but encouraged) The unique identifier used within your own application for this customer
    # 
    def create_customer(info={})
      response = Hashie::Mash.new(post("/customers.json", :body => {:customer => info}.to_json))
      return response.customer if response.customer
      response
    end
    
    #
    # * first_name (Required)
    # * last_name (Required)
    # * email (Required)
    # * organization (Optional) Company/Organization name
    # * reference (Optional, but encouraged) The unique identifier used within your own application for this customer
    # 
    def update_customer(info={})
      info.stringify_keys!
      chargify_id = info.delete('id')
      response = Hashie::Mash.new(put("/customers/#{chargify_id}.json", :body => {:customer => info}))
      return response.customer unless response.customer.to_a.empty?
      response
    end
    
    def customer_subscriptions(chargify_id)
      subscriptions = get("/customers/#{chargify_id}/subscriptions.json")
      subscriptions.map{|s| Hashie::Mash.new s['subscription']}
    end
    
    def subscription(subscription_id)
      raw_response = get("/subscriptions/#{subscription_id}.json")
      return nil if raw_response.code != 200
      Hashie::Mash.new(raw_response).subscription
    end
    
    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 201, false otherwise
    def create_subscription(subscription_attributes={})
      raw_response = post("/subscriptions.json", :body => {:subscription => subscription_attributes}.to_json)
      created  = true if raw_response.code == 201
      response = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => created)
    end

    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 200, false otherwise
    def update_subscription(sub_id, subscription_attributes = {})
      raw_response = put("/subscriptions/#{sub_id}.json", :body => {:subscription => subscription_attributes}.to_json)
      updated      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => updated)
    end

    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 200, false otherwise
    def cancel_subscription(sub_id, message="")
      raw_response = delete("/subscriptions/#{sub_id}.json", :body => {:subscription => {:cancellation_message => message} }.to_json)
      deleted      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => deleted)
    end

    def reactivate_subscription(sub_id)
      raw_response = put("/subscriptions/#{sub_id}/reactivate.json", :body => "")
      reactivated  = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response) rescue Hashie::Mash.new
      (response.subscription || response).update(:success? => reactivated)
    end

    def list_products
      products = get("/products.json")
      products.map{|p| Hashie::Mash.new p['product']}
    end
    
    def product(product_id)
      Hashie::Mash.new( get("/products/#{product_id}.json")).product
    end
    
    def product_by_handle(handle)
      Hashie::Mash.new(get("/products/handle/#{handle}.json")).product
    end
    
    private
      [:get, :post, :put, :delete].each do |http_verb|
        define_method(http_verb) {|*args| self.class.send(http_verb, *args)}
      end 
  end
end
