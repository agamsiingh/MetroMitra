/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // security headers for an admin tool: no framing, no sniffing, no referrer
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'no-referrer' },
        ],
      },
    ];
  },
};
export default nextConfig;
