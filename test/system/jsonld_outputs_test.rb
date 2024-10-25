require "application_system_test_case"

class JsonldOutputsTest < ApplicationSystemTestCase
  setup do
    @jsonld_output = jsonld_outputs(:one)
  end

  test "visiting the index" do
    visit jsonld_outputs_url
    assert_selector "h1", text: "Jsonld Outputs"
  end

  test "creating a Jsonld output" do
    visit jsonld_outputs_url
    click_on "New Jsonld Output"

    fill_in "Name", with: @jsonld_output.name
    fill_in "Webpage", with: @jsonld_output.webpage_id
    click_on "Create Jsonld output"

    assert_text "Jsonld output was successfully created"
    click_on "Back"
  end

  test "updating a Jsonld output" do
    visit jsonld_outputs_url
    click_on "Edit", match: :first

    fill_in "Name", with: @jsonld_output.name
    fill_in "Webpage", with: @jsonld_output.webpage_id
    click_on "Update Jsonld output"

    assert_text "Jsonld output was successfully updated"
    click_on "Back"
  end

  test "destroying a Jsonld output" do
    visit jsonld_outputs_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Jsonld output was successfully destroyed"
  end
end
