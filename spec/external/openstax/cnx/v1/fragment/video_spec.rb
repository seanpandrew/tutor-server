require 'rails_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Cnx::V1::Fragment::Video, type: :external, vcr: VCR_OPTS do
  context 'when video is a link' do
    let!(:cnx_page_id) { '61445f78-00e2-45ae-8e2c-461b17d9b4fd' }
    let!(:cnx_page)       {
      OpenStax::Cnx::V1.with_archive_url(url: 'https://archive.cnx.org/contents/') do
        OpenStax::Cnx::V1::Page.new(id: cnx_page_id)
      end
    }
    let!(:video_fragments) {
      cnx_page.fragments.select do |f|
        f.is_a? OpenStax::Cnx::V1::Fragment::Video
      end
    }
    let!(:expected_titles) { ['Newton’s first law of motion'] }
    let!(:expected_urls) { ['https://www.khanacademy.org/science/physics/forces-newtons-laws/newtons-laws-of-motion/v/newton-s-1st-law-of-motion'] }
    let!(:expected_content) { [<<EOF.rstrip
<div data-type="note" id="eip-231" class="ost-assessed-feature ost-video ost-tag-lo-k12phys-ch04-s02-lo02 watch-physics" data-label="Watch Physics">
<div data-type="title">Newton’s first law of motion</div> 
<p id="eip-idp1646512">This video contrasts the way we thought about motion and force in the time before Galileo’s concept of inertia and <span data-type="term">Newton’s first law of motion</span> with the way we understand force and motion now. Refer to <a href="#eip-idm20864848" class="autogenerated-content">[link]</a> as you watch.
</p>
<iframe src="https://www.khanacademy.org/science/physics/forces-newtons-laws/newtons-laws-of-motion/v/newton-s-1st-law-of-motion" width="560" height="315"></iframe>

<ol id="eip-idp19850304">
<li>Galileo’s concepts<ol id="eip-idp10164288" data-number-style="lower-alpha">
<li>Things just come to a stop</li>
<li>Forces don’t act against objects</li>
</ol>
</li>
<li>Newton’s concepts<ol id="eip-idp5872736" data-number-style="lower-alpha">
<li>Objects will continue at the same speed if no opposing force</li>
<li>Weight is a force acting against an object.</li>
</ol>
</li>
</ol>

 </div>
EOF
    ] }

    it 'provides info about the video fragment' do
      video_fragments.each do |fragment|
        expect(fragment.node).not_to be_nil
        expect(fragment.title).not_to be_nil
        expect(fragment.to_html).not_to be_nil
        expect(fragment.url).not_to be_nil
      end
    end

    it "can retrieve the fragment's title" do
      expect(video_fragments.collect { |f| f.title }).to eq expected_titles
    end

    it "can retrieve the fragment's video url" do
      expect(video_fragments.collect { |f| f.url }).to eq expected_urls
    end

    it "can retrieve the fragment's content" do
      # The content should remove the link tag but keep the tag content
      expect(video_fragments.collect { |f| f.to_html }).to eq expected_content
    end
  end

  context 'when video is embedded' do
    let!(:cnx_page_id) { '092bbf0d-0729-42ce-87a6-fd96fd87a083' }
    let!(:cnx_page) { OpenStax::Cnx::V1::Page.new(id: cnx_page_id) }
    let!(:video_fragments) {
      cnx_page.fragments.select do |f|
        f.is_a? OpenStax::Cnx::V1::Fragment::Video
      end
    }
    let!(:expected_titles) { ["A Note called Watch Physics with YouTube Embedded"] }
    let!(:expected_urls) { ['https://www.youtube.com/embed/40ETbLVkLKc'] }
    let!(:expected_content) { [<<EOF.rstrip
<div data-type="note" id="fs-id1172194442505" class="ost-assessed-feature ost-video" data-label="Watch Physics">
<div data-type="title">A Note called Watch Physics with YouTube Embedded</div>
<p id="fs-id1172194612937">Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
<iframe width="560" height="315" src="https://www.youtube.com/embed/40ETbLVkLKc"></iframe>
</div>
EOF
    ] }

    it 'provides info about the video fragment' do
      video_fragments.each do |fragment|
        expect(fragment.node).not_to be_nil
        expect(fragment.title).not_to be_nil
        expect(fragment.to_html).not_to be_nil
        expect(fragment.url).not_to be_nil
      end
    end

    it "can retrieve the fragment's title" do
      expect(video_fragments.collect { |f| f.title }).to eq expected_titles
    end

    it "can retrieve the fragment's video url" do
      expect(video_fragments.collect { |f| f.url }).to eq expected_urls
    end

    it "can retrieve the fragment's content" do
      # The content should remove the iframe tag
      expect(video_fragments.collect { |f| f.to_html }).to eq expected_content
    end
  end
end
