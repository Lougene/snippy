import Foundation

/// Strips tracking parameters and redirect wrappers from copied links while
/// keeping everything that identifies the page: scheme, host, path, meaningful
/// query parameters, and the fragment.
///
/// Pure Foundation (no AppKit) so it can be unit-tested in isolation.
enum URLCleaner {
    /// Returns a cleaned copy of `text` when it is a single http(s) URL carrying
    /// removable tracking. Returns nil when `text` isn't a lone URL or there's
    /// nothing to strip, so callers can leave the clipboard untouched.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 8192,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let comps = URLComponents(string: trimmed),
              isWebURL(comps)
        else { return nil }
        guard let cleaned = cleanComponents(comps)?.string,
              cleaned != trimmed
        else { return nil }
        return cleaned
    }

    // MARK: - Pipeline

    /// Returns the cleaned components, or nil when nothing changed.
    private static func cleanComponents(_ input: URLComponents, depth: Int = 0) -> URLComponents? {
        let host = (input.host ?? "").lowercased()

        // Redirect wrappers (Google /url, Facebook l.php, Outlook Safe Links, …)
        // hide the real destination in a query parameter. Unwrap, then clean that.
        if depth < 3, let target = unwrapRedirect(input, host: host) {
            return cleanComponents(target, depth: depth + 1) ?? target
        }

        var comps = input
        var changed = rewritePath(&comps, host: host)

        if let items = comps.percentEncodedQueryItems {
            let path = comps.path
            let kept = items.filter { !shouldStrip($0.name, host: host, path: path) }
            if kept.count != items.count {
                comps.percentEncodedQueryItems = kept.isEmpty ? nil : kept
                changed = true
            }
        }
        return changed ? comps : nil
    }

    private static func isWebURL(_ comps: URLComponents) -> Bool {
        guard let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host, !host.isEmpty
        else { return false }
        return true
    }

    // MARK: - Redirect wrappers

    private static func unwrapRedirect(_ comps: URLComponents, host: String) -> URLComponents? {
        let path = comps.path
        let params: [String]
        if isGoogle(host) && path == "/url" {
            params = ["q", "url"]
        } else if (host == "l.facebook.com" || host == "lm.facebook.com") && path == "/l.php" {
            params = ["u"]
        } else if host == "l.instagram.com" {
            params = ["u"]
        } else if host.hasSuffix("safelinks.protection.outlook.com") {
            params = ["url"]
        } else if matches(host, "youtube.com") && path == "/redirect" {
            params = ["q"]
        } else if matches(host, "linkedin.com") && path.hasPrefix("/redir/redirect") {
            params = ["url"]
        } else if host == "out.reddit.com" {
            params = ["url"]
        } else {
            return nil
        }
        for name in params {
            if let value = comps.queryItems?.first(where: { $0.name == name })?.value,
               let target = URLComponents(string: value),
               isWebURL(target) {
                return target
            }
        }
        return nil
    }

    // MARK: - Path rewrites

    /// Collapses shopping links to their canonical product URL. Returns true if
    /// the components were modified.
    private static func rewritePath(_ comps: inout URLComponents, host: String) -> Bool {
        let original = comps

        if isAmazon(host) {
            // /Some-Product-Name/dp/B0ABC12345/ref=sr_1_3?keywords=…  →  /dp/B0ABC12345
            if let asin = firstMatch(#"/(?:dp|gp/product|gp/aw/d)/([A-Z0-9]{10})"#, in: comps.path) {
                comps.path = "/dp/\(asin)"
                comps.percentEncodedQuery = nil
                comps.fragment = nil
            } else if let range = comps.path.range(of: #"/ref=[^/]*$"#, options: .regularExpression) {
                comps.path.removeSubrange(range)
            }
        } else if isEbay(host) {
            // /itm/Some-Title/123456789012?_trkparms=…  →  /itm/123456789012
            if let id = firstMatch(#"/itm/(?:[^/]+/)?(\d{9,})"#, in: comps.path) {
                comps.path = "/itm/\(id)"
                comps.percentEncodedQuery = nil
            }
        }
        return comps != original
    }

    // MARK: - Query parameters

    private static func shouldStrip(_ rawName: String, host: String, path: String) -> Bool {
        let name = rawName.lowercased()

        // Google search result URLs are ~90% session junk. Keep only what
        // reproduces the search.
        if isGoogle(host) && path == "/search" {
            return !googleSearchKeep.contains(name)
        }
        if trackingParams.contains(name) { return true }
        if trackingPrefixes.contains(where: { name.hasPrefix($0) }) { return true }
        for rule in siteRules where rule.domains.contains(where: { matches(host, $0) }) {
            if rule.params.contains(name) { return true }
        }
        if isAmazon(host) && (amazonParams.contains(name)
                              || name.hasPrefix("pf_rd_")
                              || name.hasPrefix("pd_rd_")) {
            return true
        }
        return false
    }

    /// Tracking parameters that are never meaningful to the destination page.
    private static let trackingParams: Set<String> = [
        // Ad click IDs
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid",
        "twclid", "ttclid", "li_fat_id", "yclid", "ysclid", "epik", "irclickid",
        "irgwc", "rb_clickid", "gad_source", "gad_campaignid", "srsltid",
        // Email / marketing platforms
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp",
        "hsctatracking", "mkt_tok", "vero_id", "vero_conv", "ml_subscriber",
        "ml_subscriber_hash", "ss_email_id", "ss_campaign_id", "ss_campaign_name",
        "ss_campaign_sent_date", "_kx", "dm_i", "sms_click", "sms_source", "sms_uph",
        "oly_anon_id", "oly_enc_id", "wickedid", "_bta_tid", "_bta_c",
        // Analytics
        "_ga", "_gl", "_openstat", "s_cid", "s_kwcid", "xtor", "ncid", "cmpid",
        "sr_share", "spm", "scm", "zanpid", "_branch_match_id", "_branch_referrer",
        "pk_campaign", "pk_kwd", "pk_keyword", "pk_source", "pk_medium",
        "pk_content", "pk_cid",
        // Share / referral junk
        "igshid", "igsh", "mibextid", "fb_action_ids", "fb_action_types",
        "fb_ref", "fb_source", "action_object_map", "action_type_map",
        "action_ref_map", "redirect_log_mongo_id", "redirect_mongo_id",
        "sb_referer_host",
    ]

    private static let trackingPrefixes: [String] = [
        "utm_", "mtm_", "hsa_", "itm_", "__cft__", "__tn__",
    ]

    private struct SiteRule {
        let domains: [String]
        let params: Set<String>
    }

    /// Parameters that are tracking only on specific sites (e.g. `si`, `t`, `ref`
    /// are meaningful elsewhere — GitHub uses `ref` for branches).
    private static let siteRules: [SiteRule] = [
        SiteRule(domains: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
                 params: ["si", "feature", "pp", "ab_channel", "source_ve_path",
                          "embeds_referring_euri", "embeds_referring_origin"]),
        SiteRule(domains: ["spotify.com"],
                 params: ["si", "nd", "sp_cid", "go"]),
        SiteRule(domains: ["twitter.com", "x.com"],
                 params: ["s", "t", "ref_src", "ref_url"]),
        SiteRule(domains: ["linkedin.com"],
                 params: ["trk", "trkinfo", "trackingid", "lipi", "midtoken",
                          "midsig", "eid", "otptoken", "refid"]),
        SiteRule(domains: ["tiktok.com"],
                 params: ["_r", "_t", "_d", "is_from_webapp", "sender_device",
                          "share_app_id", "share_link_id", "share_item_id", "u_code",
                          "tt_from", "refer", "is_copy_url", "timestamp", "user_id",
                          "sec_user_id", "checksum", "social_sharing", "web_id",
                          "preview_pb"]),
        SiteRule(domains: ["reddit.com"],
                 params: ["share_id", "rdt", "ref", "ref_source"]),
        SiteRule(domains: ["medium.com"],
                 params: ["source"]),
        SiteRule(domains: ["bing.com"],
                 params: ["form", "sp", "pq", "sc", "qs", "sk", "cvid", "ghsh",
                          "ghacc", "ghpl"]),
        SiteRule(domains: ["aliexpress.com"],
                 params: ["algo_pvid", "algo_exp_id", "pdp_npi", "pdp_ext_f",
                          "sourcetype", "gatewayadapt", "_randl_shipto"]),
    ]

    private static let amazonParams: Set<String> = [
        "ref", "ref_", "qid", "sr", "crid", "sprefix", "dib", "dib_tag",
        "content-id", "_encoding", "linkcode", "linkid", "camp", "creative",
        "creativeasin", "ascsubtag", "social_share", "skiptwisterog",
        "starsleft", "smid",
    ]

    private static let googleSearchKeep: Set<String> = [
        "q", "tbm", "tbs", "start", "hl", "gl", "udm", "num",
    ]

    // MARK: - Host matching

    /// True if `host` is `domain` or a subdomain of it.
    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func isGoogle(_ host: String) -> Bool {
        host.range(of: #"(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
    }

    private static func isAmazon(_ host: String) -> Bool {
        host.range(of: #"(^|\.)amazon\.[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
    }

    private static func isEbay(_ host: String) -> Bool {
        host.range(of: #"(^|\.)ebay\.[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
