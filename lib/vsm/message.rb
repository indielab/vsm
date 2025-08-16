# frozen_string_literal: true
module VSM
  # kind: :user, :assistant_delta, :assistant, :tool_call, :tool_result, :plan, :policy, :audit, :confirm_request, :confirm_response
  # path: optional addressing, e.g., [:airb, :operations, :fs]
  Message = Struct.new(:kind, :payload, :path, :corr_id, :meta, keyword_init: true)
end
