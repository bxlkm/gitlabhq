shared_examples 'cluster application status specs' do |application_name|
  describe '#status' do
    let(:cluster) { create(:cluster, :provided_by_gcp) }

    subject { described_class.new(cluster: cluster) }

    it 'sets a default status' do
      expect(subject.status_name).to be(:not_installable)
    end

    context 'when application helm is scheduled' do
      before do
        create(:clusters_applications_helm, :scheduled, cluster: cluster)
      end

      it 'defaults to :not_installable' do
        expect(subject.status_name).to be(:not_installable)
      end
    end

    context 'when application is scheduled' do
      before do
        create(:clusters_applications_helm, :installed, cluster: cluster)
      end

      it 'sets a default status' do
        expect(subject.status_name).to be(:installable)
      end
    end
  end

  describe 'status state machine' do
    describe '#make_installing' do
      subject { create(application_name, :scheduled) }

      it 'is installing' do
        subject.make_installing!

        expect(subject).to be_installing
      end
    end

    describe '#make_installed' do
      subject { create(application_name, :installing) }

      it 'is installed' do
        subject.make_installed!

        expect(subject).to be_installed
      end

      it 'updates helm version' do
        subject.cluster.application_helm.update!(version: '1.2.3')

        subject.make_installed!

        subject.cluster.application_helm.reload

        expect(subject.cluster.application_helm.version).to eq(Gitlab::Kubernetes::Helm::HELM_VERSION)
      end
    end

    describe '#make_updated' do
      subject { create(application_name, :updating) }

      it 'is updated' do
        subject.make_updated!

        expect(subject).to be_updated
      end

      it 'updates helm version' do
        subject.cluster.application_helm.update!(version: '1.2.3')

        subject.make_updated!

        subject.cluster.application_helm.reload

        expect(subject.cluster.application_helm.version).to eq(Gitlab::Kubernetes::Helm::HELM_VERSION)
      end
    end

    describe '#make_errored' do
      subject { create(application_name, :installing) }
      let(:reason) { 'some errors' }

      it 'is errored' do
        subject.make_errored(reason)

        expect(subject).to be_errored
        expect(subject.status_reason).to eq(reason)
      end
    end

    describe '#make_scheduled' do
      subject { create(application_name, :installable) }

      it 'is scheduled' do
        subject.make_scheduled

        expect(subject).to be_scheduled
      end

      describe 'when was errored' do
        subject { create(application_name, :errored) }

        it 'clears #status_reason' do
          expect(subject.status_reason).not_to be_nil

          subject.make_scheduled!

          expect(subject.status_reason).to be_nil
        end
      end
    end
  end

  describe '#available?' do
    using RSpec::Parameterized::TableSyntax

    where(:trait, :available) do
      :not_installable  | false
      :installable      | false
      :scheduled        | false
      :installing       | false
      :installed        | true
      :updating         | false
      :updated          | true
      :errored          | false
      :update_errored   | false
      :timeouted        | false
    end

    with_them do
      subject { build(application_name, trait) }

      if params[:available]
        it { is_expected.to be_available }
      else
        it { is_expected.not_to be_available }
      end
    end
  end
end
