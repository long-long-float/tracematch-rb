RSpec.describe Tracematch::RegularExpressionEngine do
  context 'match?' do
    context 'autosave' do
      let (:regex) {
        Tracematch::RegularExpressionEngine.new('action [3]')
      }

      it 'returns true' do
        expect(regex.match?(%i(action action action))).to be true
        expect(regex.match?(%i(action save action action action))).to be true
        expect(regex.match?(%i(save action save action action action))).to be true
      end

      it 'returns false' do
        expect(regex.match?(%i(action save action action))).to be false
      end
    end

    context 'contextual logging' do
      let(:regex) {
        Tracematch::RegularExpressionEngine.new('login query+')
      }

      it 'returns true' do
        expect(regex.match?(%i(login query query query))).to be true
        expect(regex.match?(%i(login query))).to be true
      end

      it 'returns false' do
        expect(regex.match?(%i(login))).to be false
        expect(regex.match?(%i(login logout))).to be false
      end
    end

    context 'observer' do
      let(:regex) {
        Tracematch::RegularExpressionEngine.new('create_observer update_subject*')
      }

      it 'returns true' do
        expect(regex.match?(%i(create_observer))).to be true
        expect(regex.match?(%i(create_observer update_subject))).to be true
        expect(regex.match?(%i(create_observer update_subject update_subject))).to be true
      end

      it 'returns false' do
        expect(regex.match?(%i(update_subject))).to be false
      end
    end

    context 'safe iterators' do
      let(:regex) {
        Tracematch::RegularExpressionEngine.new('create_iter call_next* update_source+ call_next')
      }

      it 'returns true' do
        expect(regex.match?(%i(create_iter call_next update_source call_next))).to be true
        expect(regex.match?(%i(create_iter update_source call_next))).to be true
        expect(regex.match?(%i(create_iter call_next call_next update_source call_next))).to be true
        expect(regex.match?(%i(create_iter call_next call_next update_source update_source call_next))).to be true
      end

      it 'returns false' do
        expect(regex.match?(%i(create_iter call_next))).to be false
        expect(regex.match?(%i(create_iter call_next update_source))).to be false
        expect(regex.match?(%i(create_iter call_next update_source call_next update_source))).to be false
      end
    end

    context 'connection management' do
      let(:regex) {
        Tracematch::RegularExpressionEngine.new('(create query) | (close_con query)')
      }

      it 'returns true' do
        expect(regex.match?(%i(create query))).to be true
        expect(regex.match?(%i(close_con query))).to be true
        expect(regex.match?(%i(create query close_con query))).to be true
        expect(regex.match?(%i(create close_con query))).to be true
      end

      it 'returns false' do
        expect(regex.match?(%i(create query query))).to be false
        expect(regex.match?(%i(create close_con))).to be false
      end
    end
  end
end

