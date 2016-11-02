require 'google/apis/sheets_v4'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require "net/http"
require "uri"
require 'fileutils'
require 'json'
require 'thread'

def getNexmoDetails
  puts "Enter the NEXMO API_KEY"
  key = gets.chomp
  puts "ENTER the NEXMO API_SECRET"
  secret = gets.chomp
  return key,secret
end

def authorize
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

  client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(
    client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(
      base_url: OOB_URI)
    puts "Open the following URL in the browser and enter the " +
         "resulting code after authorization"
    puts url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI)
  end
  credentials
end

def getSheetId
  puts "Enter sheet id"
  id = gets.chomp
  return id
end

def getFromNumber
  puts "Enter Sender number"
  no = gets.chomp
  return no
end

def sendToNexmo(to, from, text, to_retry)
  if to_retry
    p " Retrying ..."
  end
  uri = URI.parse("https://rest.nexmo.com/sms/json")
  error = false
  statusCode = "0"

  params = {
      'api_key' => API_KEY,
      'api_secret' => API_SECRET,
      'to' => to,
      'from' => from,
      'text'=> text
  }
  response = Net::HTTP.post_form(uri, params)

  if response.kind_of? Net::HTTPOK
    decoded_response = JSON.parse(response.body )

    messagecount = decoded_response["message-count"]

    decoded_response["messages"].each do |message|
      statusCode = message["status"]
      if statusCode == "0"
        puts "SENT!\n"
      else
        puts "FAILED : " + message["error-text"]
      end
    end
  else
    statusCode = response.code
    puts statusCode + " error sending message"
  end
  return statusCode.to_i
end

def getTitleHash titles, relevant_titles
  title_hash = {}

  titles.each_with_index do |title, i|
    if relevant_titles.include? title
      title_hash[title] = i
    end
  end

  return title_hash
end

def start(data, title_hash, delivered_status, land_line, from_number, nexmoRetryDelay, nexmoThrottledStatusCode)
  puts "======================\n\n"
  for i in 1..data.length
      to = data[i][title_hash['To']]
      status = data[i][title_hash['Status']]
      network = data[i][title_hash['Network']]
      message = data[i][title_hash['Body']]
      beta = data[i][title_hash['Beta']]
      invite = data[i][title_hash['Invite']]
      update = data[i][title_hash['Update']]

      if (status != delivered_status) && !(network.include? land_line) && (beta == "TRUE" || invite == "TRUE" || update == "TRUE")
        puts "Sending to " + to + " ..."
        statusCode = sendToNexmo(to, from_number, message, false)
        if statusCode > 0 && statusCode == nexmoThrottledStatusCode
          sleep(nexmoRetryDelay)
          sendToNexmo(to, from_number, message, true)
        end
        puts "\n"
      end
  end
end


OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
APPLICATION_NAME = 'Invite Flow Checklist'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.pwd, '.credentials',
                             "sheets.invite-flow.yaml")
SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY


API_KEY, API_SECRET = getNexmoDetails



spreadsheet_id = getSheetId
from = getFromNumber
fetch_range = 'SMS Log 10/23-10/28'

# Initialize the API
service = Google::Apis::SheetsV4::SheetsService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize


response = service.get_spreadsheet_values(spreadsheet_id, fetch_range)
titles = response.values[0]
data = response.values
delivered_status = "DELIVRD"
land_line = "FIXED"
nexmoRetryDelay = 2
nexmoThrottledStatusCode = 1

relevant_titles = ["To", "Status", "Network", "Body", "Beta", "Invite", "Update"]
title_hash = getTitleHash(titles, relevant_titles)

start(data, title_hash, delivered_status, land_line, from, nexmoRetryDelay, nexmoThrottledStatusCode)
