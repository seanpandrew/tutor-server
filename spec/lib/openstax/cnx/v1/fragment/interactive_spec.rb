require 'rails_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Cnx::V1::Fragment::Interactive, type: :external, vcr: VCR_OPTS do
  let!(:cnx_page_id)           { '640e3e84-09a5-4033-b2a7-b7fe5ec29dc6@4' }
  let!(:cnx_page)              { OpenStax::Cnx::V1::Page.new(id: cnx_page_id) }
  let!(:interactive_fragments) {
    feature_fragments = cnx_page.fragments.select do |f|
      f.is_a? OpenStax::Cnx::V1::Fragment::Feature
    end
    feature_fragments.collect do |feature_fragment|
      feature_fragment.fragments.select do |f|
        f.is_a? OpenStax::Cnx::V1::Fragment::Interactive
      end
    end.flatten
  }
  let!(:expected_titles) { [ nil ] }
  let!(:expected_urls) { [ 'https://phet.colorado.edu/sims/html/forces-and-motion-basics/latest/forces-and-motion-basics_en.html' ] }
  let!(:expected_content) { [
<<EOF.rstrip
<div data-type="note" data-has-label="true" id="fs-idp38765984" class="note ost-assessed-feature os-interactive virtual-physics ost-tag-lo-k12phys-ch04-s01-lo02" data-label="Virtual Physics: Forces and Motion: Basics">
<p id="fs-idp92213536">In this simulation, you will first explore net force by placing blue people on the left side of a tug of war rope and red people on the right side of the rope (by clicking people and dragging them with your mouse). Experiment with changing the number and size of people on each side to see how it affects the outcome of the match and the net force. Hit the Go! button to start the match, and the “reset all” button to start over.</p>
<p id="fs-idp72378080">Next, click on the Friction tab. Try selecting different objects for the person to push. Slide the applied force button to the right to apply force to the right and to the left to apply force to the left. The force will continue to be applied as long as you hold down the button. See the arrow representing friction change in magnitude and direction, depending on how much force you apply. Try increasing or decreasing the friction force to see how this change affects the motion.</p>
<iframe src="https://phet.colorado.edu/sims/html/forces-and-motion-basics/latest/forces-and-motion-basics_en.html" width="960" height="560"></iframe>
 </div>
EOF
  ] }

  it 'provides info about the interactive fragment' do
    interactive_fragments.each do |fragment|
      expect(fragment.node).not_to be_nil
      expect(fragment.title).to be_nil
      expect(fragment.to_html).not_to be_nil
      expect(fragment.url).not_to be_nil
    end
  end

  it "can retrieve the fragment's title" do
    expect(interactive_fragments.collect { |f| f.title }).to eq(expected_titles)
  end

  it "can retrieve the fragment's interactive url" do
    expect(interactive_fragments.collect { |f| f.url }).to eq(expected_urls)
  end

  it "can retrieve the fragment's content" do
    expect(interactive_fragments.collect { |f| f.to_html }).to eq(expected_content)
  end
end