/// 访问自建 Supabase 中转（备用地址）所需的令牌，构建时通过
/// `--dart-define=SUPABASE_PROXY_TOKEN=...` 注入；未注入时为空，备用地址不可用。
const String supabaseProxyToken = String.fromEnvironment('SUPABASE_PROXY_TOKEN');
