# frozen_string_literal: true
# require "spec_helper"
#
# RSpec.describe VSM::Identity do
#   include Async::RSpec::Reactor
#
#   it "receives alert for algedonic messages through capsule dispatch" do
#     spy = SpyIdentity.new(identity: "top")
#     cap = VSM::Capsule.new(
#       name: :top,
#       roles: {
#         identity: spy,
#         governance: VSM::Governance.new,
#         coordination: VSM::Coordination.new,
#         intelligence: VSM::Intelligence.new,
#         operations: VSM::Operations.new
#       },
#       children: {}
#     )
#
#     cap.run
#     cap.bus.emit VSM::Message.new(kind: :user, payload: "oops", meta: { severity: :algedonic })
#
#     Async { |t| t.sleep 0.05 }
#     expect(spy.alerts.size).to be >= 1
#     expect(spy.alerts.first.kind).to eq(:user)
#   end
# end
#
