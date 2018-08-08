resource "google_compute_global_forwarding_rule" "http" {
  project = "${var.project}"

  ##Create this resource if "http_forward" is set to "true"
  count      = "${var.http_forward ? 1 : 0}"
  name       = "${var.lb_name}-gfr-http"
  target     = "${google_compute_target_http_proxy.default.self_link}"
  ip_address = "${google_compute_global_address.default.address}"
  port_range = "80"
  depends_on = ["google_compute_global_address.default"]
}

resource "google_compute_global_forwarding_rule" "https" {
  project = "${var.project}"

  ##Create this resource if "ssl" is set to "true"
  count      = "${var.ssl ? 1 : 0}"
  name       = "${var.lb_name}-gfr-https"
  target     = "${google_compute_target_https_proxy.default.self_link}"
  ip_address = "${google_compute_global_address.default.address}"
  port_range = "443"
  depends_on = ["google_compute_global_address.default"]
}

resource "google_compute_global_address" "default" {
  project    = "${var.project}"
  name       = "${var.lb_name}-gip"
  ip_version = "${var.ip_version}"
}

# HTTP proxy when ssl is false
resource "google_compute_target_http_proxy" "default" {
  project = "${var.project}"
  count   = "${var.http_forward ? 1 : 0}"
  name    = "${var.lb_name}-http-proxy"
  url_map = "${element(compact(concat(list(var.url_map), google_compute_url_map.default.*.self_link)), 0)}"
}

# HTTPS proxy  when ssl is true
resource "google_compute_target_https_proxy" "default" {
  project          = "${var.project}"
  count            = "${var.ssl ? 1 : 0}"
  name             = "${var.lb_name}-https-proxy"
  url_map          = "${element(compact(concat(list(var.url_map), google_compute_url_map.default.*.self_link)), 0)}"
  ssl_certificates = ["${compact(concat(var.ssl_certificates, google_compute_ssl_certificate.default.*.self_link))}"]
}

resource "google_compute_ssl_certificate" "default" {
  project     = "${var.project}"
  count       = "${(var.ssl && !var.use_ssl_certificates) ? 1 : 0}"
  name_prefix = "${var.lb_name}-certificate-"
  private_key = "${var.private_key}"
  certificate = "${var.certificate}"

  lifecycle = {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "default" {
  project         = "${var.project}"
  count           = "${var.create_url_map ? 1 : 0}"
  name            = "${var.lb_name}-um"
  default_service = "${google_compute_backend_service.default.0.self_link}"
}

resource "google_compute_backend_service" "default" {
  project         = "${var.project}"
  count           = "${length(var.backend_params)}"
  name            = "${var.lb_name}-be-${count.index}"
  port_name       = "${element(split(",", element(var.backend_params, count.index)), 1)}"
  protocol        = "HTTP"
  timeout_sec     = "${element(split(",", element(var.backend_params, count.index)), 3)}"
  backend         = ["${var.backends["${count.index}"]}"]
  health_checks   = ["${element(google_compute_http_health_check.default.*.self_link, count.index)}"]
  security_policy = "${var.security_policy}"
}

resource "google_compute_http_health_check" "default" {
  project      = "${var.project}"
  count        = "${length(var.backend_params)}"
  name         = "${var.lb_name}-http-hc-${count.index}"
  request_path = "${element(split(",", element(var.backend_params, count.index)), 0)}"
  port         = "${element(split(",", element(var.backend_params, count.index)), 2)}"
}

resource "google_compute_firewall" "default-hc" {
  count         = "${length(var.shared_vpc_name)}"
  project       = "${var.shared_vpc_enabled ? var.shared_vpc_project : var.project}"
  count         = "${length(var.backend_params)}"
  name          = "${var.lb_name}-gcp-hc-${count.index}"
  network       = "${element(var.shared_vpc_name, count.index)}"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags   = ["${var.target_tags}"]

  allow {
    protocol = "tcp"
    ports    = ["${element(split(",", element(var.backend_params, count.index)), 2)}"]
  }
}
