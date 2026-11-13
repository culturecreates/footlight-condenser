require 'test_helper'

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @message = messages(:one)
  end

  test "should get index" do
    get messages_url
    assert_response :success
  end

  test "should get new" do
    get new_message_url
    assert_response :success
  end

  test "should create message" do
    assert_difference('Message.count') do
      post messages_url, params: { message: { artifact: @message.artifact, message: @message.message } }
    end

    assert_redirected_to message_url(Message.last)
  end

  test "should show message" do
    get message_url(@message)
    assert_response :success
  end

  test "should get edit" do
    get edit_message_url(@message)
    assert_response :success
  end

  test "should update message" do
    patch message_url(@message), params: { message: { artifact: @message.artifact, message: @message.message } }
    assert_redirected_to message_url(@message)
  end

  test "should destroy message" do
    assert_difference('Message.count', -1) do
      delete message_url(@message)
    end

    assert_redirected_to messages_url
  end

  test "site filtered messages paginate at 100 with stable ordering and preserve the site" do
    site = websites(:two)
    Message.insert_all!(103.times.map { |i| { artifact: site.seedurl, message: "Paged message #{i}", created_at: Time.current, updated_at: Time.current } })
    expected = Message.where(artifact: site.seedurl).order(created_at: :desc, id: :desc).pluck(:id)
    Distillator::FetchService.expects(:fetch).never
    Distillator::TransitionCheckJob.expects(:perform_later).never

    get messages_url, params: { seedurl: site.seedurl }
    assert_response :success
    assert_select 'table.messages-table tbody tr', count: 100
    first_ids = response.parsed_body.css('table.messages-table a').select { |link| link.text == "Show" }.map { |link| link['href'].split('/').last.to_i }
    assert_equal expected.first(100), first_ids
    assert_select "a[rel=next][href*='seedurl=#{site.seedurl}'][href*='page=2']"

    get messages_url, params: { seedurl: site.seedurl, page: 2 }
    assert_response :success
    assert_select 'table.messages-table tbody tr', count: expected.drop(100).length
    second_ids = response.parsed_body.css('table.messages-table a').select { |link| link.text == "Show" }.map { |link| link['href'].split('/').last.to_i }
    assert_equal expected.drop(100), second_ids
    assert_empty first_ids & second_ids
  end

  test "site filter matches the artifact exactly and retains history for removed sites" do
    Message.create!(artifact: "removed-site", message: "Old export report")
    Message.create!(artifact: "removed-site-other", message: "Different site's report")
    get messages_url, params: { seedurl: "removed-site", page: 1 }
    assert_response :success
    assert_select "select[name=seedurl] option[value='removed-site'][selected]"
    assert_select 'table.messages-table tbody tr', count: 1
    assert_includes response.body, "Old export report"
    assert_not_includes response.body, "Different site&#39;s report"
    assert_select 'form[action="/messages"] input[name=page]', count: 0
    assert_select 'a[href="/messages"]', text: "Clear filter"
  end

  test "global list and JSON are paginated and invalid paging cannot load the whole table" do
    Message.insert_all!(105.times.map { |i| { artifact: "global-pages", message: "Global #{i}", created_at: Time.current, updated_at: Time.current } })
    get messages_url, params: { page: "bad", per_page: 100000 }
    assert_response :success
    assert_select 'table.messages-table tbody tr', count: 100
    get messages_url(format: :json), params: { seedurl: "global-pages", page: 2 }
    assert_response :success
    assert_equal 5, response.parsed_body.length
    assert response.parsed_body.all? { |message| message['artifact'] == "global-pages" }
  end
end
