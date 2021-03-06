require 'app_spec_helper'

describe EbtBalanceSmsApp, :type => :feature do
  describe 'initial text' do
    let(:texter_number) { "+12223334444" }
    let(:inbound_twilio_number) { "+15556667777" }
    let(:fake_twilio) { double("FakeTwilioService", :make_call => 'made call', :send_text => 'sent text') }
    let(:to_state) { 'CA' }

    context 'with valid EBT number' do
      let(:ebt_number) { "1111222233334444" }
      let(:fake_state_handler) { double('FakeStateHandler', :phone_number => 'fake_state_phone_number', :button_sequence => "fake_button_sequence", :extract_valid_ebt_number_from_text => ebt_number ) }

      before do
        allow(TwilioService).to receive(:new).and_return(fake_twilio)
        allow(StateHandler).to receive(:for).with(to_state).and_return(fake_state_handler)
        post '/', { "Body" => ebt_number, "From" => texter_number, "To" => inbound_twilio_number, "ToState" => to_state }
      end

      it 'initializes a new state handler' do
        expect(StateHandler).to have_received(:for).with(to_state)
      end

      it "calls the handler's button_sequence() method with the ebt_number" do
        expect(fake_state_handler).to have_received(:button_sequence).with(ebt_number)
      end

      it 'uses the handler to extract the EBT card number' do
        expect(fake_state_handler).to have_received(:extract_valid_ebt_number_from_text).with(ebt_number)
      end

      it 'initiates an outbound Twilio call to EBT line with correct details' do
        expect(fake_twilio).to have_received(:make_call).with(
          url: "http://example.org/get_balance?phone_number=#{texter_number}&twilio_phone_number=#{inbound_twilio_number}&state=#{to_state}",
          to: fake_state_handler.phone_number,
          send_digits: fake_state_handler.button_sequence,
          from: inbound_twilio_number,
          method: 'GET'
        )
      end

      it 'sends a text to the user telling them wait time' do
        expect(fake_twilio).to have_received(:send_text).with(
          to: texter_number,
          from: inbound_twilio_number,
          body: "Thanks! Please wait 1-2 minutes while we check your EBT balance."
        )
      end

      it 'responds with 200 status' do
        expect(last_response.status).to eq(200)
      end
    end

    context 'with INVALID EBT number' do
      let(:invalid_ebt_number) { "111122223333" }
      let(:fake_state_handler) { double('FakeStateHandler', :phone_number => 'fake_state_phone_number', :button_sequence => "fake_button_sequence", :extract_valid_ebt_number_from_text => :invalid_number ) }

      before do
        allow(TwilioService).to receive(:new).and_return(fake_twilio)
        allow(StateHandler).to receive(:for).with(to_state).and_return(fake_state_handler)
        post '/', { "Body" => invalid_ebt_number, "From" => texter_number, "To" => inbound_twilio_number, "ToState" => to_state }
      end

      it 'sends a text to the user with error message' do
        expect(fake_twilio).to have_received(:send_text).with(
          to: texter_number,
          from: inbound_twilio_number,
          body: "Sorry, that EBT number doesn't look right. Please try again."
        )
      end

      it 'responds with 200 status' do
        expect(last_response.status).to eq(200)
      end
    end

    context 'using Spanish-language Twilio phone number' do
      let(:ebt_number) { "1111222233334444" }
      let(:spanish_twilio_number) { "+19998887777" }
      let(:inbound_twilio_number) { spanish_twilio_number }
      let(:fake_state_handler) { double('FakeStateHandler', :phone_number => 'fake_state_phone_number', :button_sequence => "fake_button_sequence", :extract_valid_ebt_number_from_text => ebt_number ) }
      let(:spanish_message_generator) { double('SpanishMessageGenerator', :thanks_please_wait => 'spanish thankspleasewait') }

      before do
        allow(TwilioService).to receive(:new).and_return(fake_twilio)
        allow(StateHandler).to receive(:for).with(to_state).and_return(fake_state_handler)
        allow(MessageGenerator).to receive(:new).with(:spanish).and_return(spanish_message_generator)
        post '/', { "Body" => ebt_number, "From" => texter_number, "To" => inbound_twilio_number, "ToState" => to_state }
      end

      it 'sends a text IN SPANISH to the user telling them wait time' do
        expect(fake_twilio).to have_received(:send_text).with(
          to: texter_number,
          from: inbound_twilio_number,
          body: spanish_message_generator.thanks_please_wait
        )
      end

      it 'responds with 200 status' do
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'GET /get_balance' do
    let(:texter_number) { "+12223334444" }
    let(:inbound_twilio_number) { "+15556667777" }
    let(:state) { 'CA' }

    before do
      get "/get_balance?phone_number=#{texter_number}&twilio_phone_number=#{inbound_twilio_number}&state=#{state}"
      parsed_response = Nokogiri::XML(last_response.body)
      record_attributes = parsed_response.children.children[0].attributes
      @callback_url = record_attributes["transcribeCallback"].value
      @maxlength = record_attributes["maxLength"].value
    end

    it 'responds with callback to correct URL (ie, correct phone number)' do
      expect(@callback_url).to eq("http://example.org/CA/12223334444/15556667777/send_balance")
    end

    it 'has max recording length set correctly' do
      expect(@maxlength).to eq("18")
    end

    it 'responds with 200 status' do
      expect(last_response.status).to eq(200)
    end
  end

  describe 'sending the balance to user' do
    let(:to_phone_number) { "19998887777" }
    let(:twilio_number) { "+15556667777" }
    let(:fake_twilio) { double("FakeTwilioService", :send_text => 'sent text') }
    let(:state) { 'CA' }

    before do
      allow(TwilioService).to receive(:new).and_return(fake_twilio)
    end

    context 'when EBT number is valid' do
      let(:handler_balance_response) { 'Hi! Your balance is...' }
      let(:fake_transcriber) { double('FakeTranscriber', :transcribe_balance_response => handler_balance_response) }
      let(:fake_state_handler) { double('FakeStateHandler', :transcriber_for => fake_transcriber ) }

      before do
        allow(StateHandler).to receive(:for).with(state).and_return(fake_state_handler)
        post "/#{state}/#{to_phone_number}/#{twilio_number}/send_balance", { "TranscriptionText" => 'fake raw transcription containing balance' }
      end

      it 'sends the correct amounts to user' do
        expect(fake_twilio).to have_received(:send_text).with(
          to: to_phone_number,
          from: twilio_number,
          body: handler_balance_response
        )
      end

      it 'returns status 200' do
        expect(last_response.status).to eq(200)
      end
    end

    context 'when EBT number is NOT valid' do
      let(:handler_balance_response) { 'Sorry...' }
      let(:fake_transcriber) { double('FakeTranscriber', :transcribe_balance_response => handler_balance_response) }
      let(:fake_state_handler) { double('FakeStateHandler', :transcriber_for => fake_transcriber ) }

      before do
        allow(StateHandler).to receive(:for).with(state).and_return(fake_state_handler)
        post "/#{state}/#{to_phone_number}/#{twilio_number}/send_balance", { "TranscriptionText" => 'fake raw transcription for EBT number not found' }
      end

      it 'sends the user an error message' do
        expect(fake_twilio).to have_received(:send_text).with(
          to: to_phone_number,
          from: twilio_number,
          body: handler_balance_response
        )
      end

      it 'returns status 200' do
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'POST /get_balance' do
    before do
      post '/get_balance'
    end

    it 'responds with 200 status' do
      expect(last_response.status).to eq(200)
    end

    it 'responds with valid Twiml that does nothing' do
      desired_response = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Response>
</Response>
EOF
      expect(last_response.body).to eq(desired_response)
    end
  end

  describe 'inbound voice call' do
    let(:caller_number) { "+12223334444" }
    let(:inbound_twilio_number) { "+14156667777" }
    let(:to_state) { 'CA' }
    let(:fake_state_phone_number) { '+18882223333' }
    let(:fake_state_handler) { double('FakeStateHandler', :phone_number => fake_state_phone_number) }
    let(:fake_twilio) { double("FakeTwilioService", :send_text => 'sent text') }
    let(:fake_message_generator) { double('MessageGenerator', :inbound_voice_call_text_message => 'voice call text message') }

    before do
      allow(TwilioService).to receive(:new).and_return(fake_twilio)
      allow(StateHandler).to receive(:for).with(to_state).and_return(fake_state_handler)
      allow(MessageGenerator).to receive(:new).and_return(fake_message_generator)
      post '/voice_call', { "From" => caller_number, "To" => inbound_twilio_number, "ToState" => to_state }
    end

    it 'responds with 200 status' do
      expect(last_response.status).to eq(200)
    end

    it 'sends an outbound text to the number' do
      expect(fake_twilio).to have_received(:send_text).with(
        to: caller_number,
        from: inbound_twilio_number,
        body: fake_message_generator.inbound_voice_call_text_message
      )
    end

    it 'plays welcome message to caller and allows them to go to state line' do
      desired_response = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Gather timeout="10" action="http://twimlets.com/forward?PhoneNumber=#{fake_state_phone_number}" method="GET" numDigits="1">
    <Play>https://s3-us-west-1.amazonaws.com/balance-cfa/balance-splash.mp3</Play>
  </Gather>
  <Redirect method="GET">http://twimlets.com/forward?PhoneNumber=#{fake_state_phone_number}</Redirect>
</Response>
EOF
      expect(last_response.body).to eq(desired_response)
    end
  end
end
