# frozen_string_literal: true

class SendFormDeclinedWebhookRequestJob
  include Sidekiq::Job

  sidekiq_options queue: :webhooks

  MAX_ATTEMPTS = 10

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])
    webhook_url = WebhookUrl.find(params['webhook_url_id'])

    attempt = params['attempt'].to_i

    return if webhook_url.url.blank? || webhook_url.events.exclude?('form.declined')

    ActiveStorage::Current.url_options = Docuseal.default_url_options

    resp = SendWebhookRequest.call(webhook_url, event_type: 'form.declined',
                                                event_uuid: params['event_uuid'],
                                                record: submitter,
                                                attempt:,
                                                data: Submitters::SerializeForWebhook.call(submitter))

    if (resp.nil? || resp.status.to_i >= 400) && attempt <= MAX_ATTEMPTS &&
       (!Docuseal.multitenant? || submitter.account.account_configs.exists?(key: :plan))
      SendFormDeclinedWebhookRequestJob.perform_in((2**attempt).minutes, {
                                                     **params,
                                                     'attempt' => attempt + 1,
                                                     'last_status' => resp&.status.to_i
                                                   })
    end
  end
end
