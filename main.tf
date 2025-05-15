locals {
  pub_sub_agent = "service-${data.google_project.default.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

data "google_project" "default" {
  project_id = "bdb-org-cicd"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "pubsub.googleapis.com",
    "bigquery.googleapis.com"
  ])

  project                    = data.google_project.default.project_id
  service                    = each.value
  disable_on_destroy         = true
  disable_dependent_services = true
}

resource "google_pubsub_topic_iam_member" "agent_dead_letter_access" {
  for_each = toset([
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber"
  ])
  member  = "serviceAccount:${local.pub_sub_agent}"
  role    = each.value
  topic   = google_pubsub_topic.dead_letter_topic.id
  project = data.google_project.default.project_id
}

resource "google_service_account" "default" {
  project    = data.google_project.default.project_id
  account_id = "pubsub-bq-writer"
}

resource "google_bigquery_dataset_iam_member" "pubsub_bigquery_access" {
  project    = data.google_project.default.project_id
  dataset_id = google_bigquery_dataset.default.dataset_id
  member     = google_service_account.default.member
  role       = "roles/bigquery.admin"
}

resource "google_pubsub_topic" "dead_letter_topic" {
  project = data.google_project.default.project_id
  name    = "bq-conn-dead-topic"

  message_storage_policy {
    allowed_persistence_regions = ["europe-west1"]
    enforce_in_transit          = true
  }
}

resource "google_pubsub_topic" "default" {
  project = data.google_project.default.project_id
  name    = "bq-conn-topic"

  message_storage_policy {
    allowed_persistence_regions = ["europe-west1"]
    enforce_in_transit          = true
  }

  schema_settings {
    schema   = google_pubsub_schema.message_schema.id
    encoding = "JSON"
  }
}

resource "google_pubsub_schema" "message_schema" {
  project    = data.google_project.default.project_id
  name       = "person_message_schema"
  type       = "AVRO"
  definition = <<EOF
  {
    "type": "record",
    "name": "PersonMessage",
    "fields": [
      {"name": "lastName", "type": "string"},
      {"name": "firstName", "type": "string"},
      {"name": "rawXml", "type": "string"}
    ]
  }
EOF
}

resource "google_bigquery_dataset" "default" {
  project                    = data.google_project.default.project_id
  dataset_id                 = "target_dataset"
  friendly_name              = "Target Dataset PubSub"
  description                = "Dataset used to store messages coming from PubSub"
  delete_contents_on_destroy = true
  location                   = "europe-west1"
}

resource "google_bigquery_table" "default" {
  project             = data.google_project.default.project_id
  dataset_id          = google_bigquery_dataset.default.dataset_id
  table_id            = "messages"
  deletion_protection = false
  schema              = <<EOF
[
  {
    "name": "firstName",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "First name from the message"
  },
  {
    "name": "lastName",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Last name from the message"
  },
  {
    "name": "rawXml",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "The original XML data"
  }
]
EOF
}

resource "google_pubsub_subscription" "bq_push" {
  project = data.google_project.default.project_id
  name    = "bq-push"
  topic   = google_pubsub_topic.default.id

  bigquery_config {
    table                 = "${data.google_project.default.project_id}.${google_bigquery_dataset.default.dataset_id}.${google_bigquery_table.default.table_id}"
    use_topic_schema      = true
    write_metadata        = false
    service_account_email = google_service_account.default.email
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }

  depends_on = [
    google_bigquery_dataset_iam_member.pubsub_bigquery_access,
    google_bigquery_table.default,
    google_project_service.apis,
    google_pubsub_topic.dead_letter_topic,
    google_pubsub_topic_iam_member.agent_dead_letter_access
  ]
}