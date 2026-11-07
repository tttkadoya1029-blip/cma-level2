// Supabase の接続情報（Project Settings → API Keys）
// publishable key は公開しても安全な鍵です（データの守りはデータベース側のルールで行っています）。
// ※ service_role / secret key は絶対にここに書かないこと
window.APP_CONFIG = {
  SUPABASE_URL: "https://jmwshxdrxzvgsswupamx.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_ti06MPxNrF3bIi-KjOVUAQ_DQyuuJ3t",
  // Googleログインを使わない場合は false に
  ENABLE_GOOGLE: true
};
