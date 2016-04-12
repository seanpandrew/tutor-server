require 'rails_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Cnx::V1::Fragment::Reading, type: :external, vcr: VCR_OPTS do
  let(:reading_processing_instructions) {
    FactoryGirl.build(:content_book).reading_processing_instructions
  }
  let(:fragment_splitter) {
    OpenStax::Cnx::V1::FragmentSplitter.new(reading_processing_instructions)
  }
  let(:cnx_page_id)       { '95e61258-2faf-41d4-af92-f62e1414175a@4' }
  let(:cnx_page)          { OpenStax::Cnx::V1::Page.new(id: cnx_page_id) }
  let(:fragments)         { fragment_splitter.split_into_fragments(cnx_page.converted_root) }
  let(:reading_fragments) { fragments.select { |f| f.instance_of? described_class } }

  let(:expected_titles)   {
    [ "Section Learning Objectives; " +
      "Defining Force and Dynamics; " +
      "Free-body Diagrams and Examples of Forces" ]
  }

  it "provides info about the reading fragment" do
    reading_fragments.each do |fragment|
      expect(fragment.node).not_to be_nil
      expect(fragment.title).not_to be_blank
      expect(fragment.to_html).not_to be_blank
    end
  end

  it "can retrieve the fragment's title" do
    expect(reading_fragments.map(&:title)).to eq expected_titles
  end
end
