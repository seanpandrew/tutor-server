require 'rails_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Cnx::V1::Fragment::OptionalExercise, type: :external, vcr: VCR_OPTS do
  let(:reading_processing_instructions) {
    FactoryGirl.build(:content_book).reading_processing_instructions
  }
  let(:fragment_splitter)  {
    OpenStax::Cnx::V1::FragmentSplitter.new(reading_processing_instructions)
  }
  let(:cnx_page_id)        { '640e3e84-09a5-4033-b2a7-b7fe5ec29dc6@4' }
  let(:cnx_page)           { OpenStax::Cnx::V1::Page.new(id: cnx_page_id) }
  let(:fragments)          { fragment_splitter.split_into_fragments(cnx_page.converted_root) }
  let(:exercise_fragments) { fragments.select{ |f| f.instance_of? described_class } }

  let!(:expected_titles) { [ nil, nil ] }
  let!(:expected_codes)  {
    [ ['https://exercises-dev.openstax.org/api/exercises?q=tag%3A%22k12phys-ch04-ex017%22'],
      ['https://exercises-dev.openstax.org/api/exercises?q=tag%3A%22k12phys-ch04-ex073%22'] ]
  }
  let!(:expected_tags)   { [ ['k12phys-ch04-ex017'], ['k12phys-ch04-ex073'] ] }

  it "provides info about the optional exercise fragment" do
    exercise_fragments.each do |fragment|
      expect(fragment.node).not_to be_nil
      expect(fragment.title).to be_nil
      expect(fragment.embed_codes).not_to be_empty
      expect(fragment.embed_tags).not_to be_empty
    end
  end

  it "returns the assigned title" do
    expect(exercise_fragments.map(&:title)).to eq expected_titles
  end

  it "can retrieve the fragment's embed code" do
    expect(exercise_fragments.map(&:embed_codes)).to eq expected_codes
  end

  it "can retrieve the fragment's  embed tag" do
    expect(exercise_fragments.map(&:embed_tags)).to eq expected_tags
  end
end
