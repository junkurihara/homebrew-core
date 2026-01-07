#
# Homebrew Formula for curl + quiche
# Based on https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/curl.rb
# Forked from https://github.com/junkurihara/homebrew-cloudflare/blob/master/curl.rb
#
# brew install -s <url of curl.rb>
#
# You can add --HEAD if you want to build curl from git master (recommended)
#
# For more information, see https://developers.cloudflare.com/http3/tutorials/curl-brew
#
class Curl < Formula
  desc "Get a file from an HTTP, HTTPS or FTP server with HTTP/3 support using quiche"
  homepage "https://curl.se"
  url "https://curl.se/download/curl-8.18.0.tar.bz2"
  mirror "https://github.com/curl/curl/releases/download/curl-8_18_0/curl-8.18.0.tar.bz2"
  sha256 "ffd671a3dad424fb68e113a5b9894c5d1b5e13a88c6bdf0d4af6645123b31faf"
  license "curl"

  livecheck do
    url "https://curl.se/download/"
    regex(/href=.*?curl[._-]v?(.*?)\.t/i)
  end

  head do
    url "https://github.com/curl/curl.git"
  end

  keg_only :provided_by_macos

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "rust" => :build
  depends_on "brotli"
  depends_on "libidn2"
  depends_on "libnghttp2"
  depends_on "libssh2"
  depends_on "openldap"
  depends_on "rtmpdump"
  depends_on "zstd"

  uses_from_macos "krb5"
  uses_from_macos "zlib"

  resource "quiche" do
    url "https://github.com/cloudflare/quiche.git", branch: "master"
  end

  def install
    # Build with quiche:
    #   https://github.com/curl/curl/blob/master/docs/HTTP3.md#quiche-version
    quiche = buildpath/"quiche/quiche"
    resource("quiche").stage quiche.parent
    cd "quiche" do
      # Build static libs only
      inreplace "quiche/Cargo.toml", /^crate-type = .*/, "crate-type = [\"staticlib\"]"

      system "cargo", "build",
                      "--release",
                      "--package=quiche",
                      "--features=ffi,pkg-config-meta,qlog"
      (quiche/"deps/boringssl/src/lib").install Pathname.glob("target/release/build/*/out/build/lib{crypto,ssl}.a")
    end

    system "autoreconf", "-fi"

    args = %W[
      LDFLAGS=-Wl,-rpath,#{quiche.parent}/target/release
      --with-openssl=#{quiche}/deps/boringssl/src
      --with-quiche=#{quiche.parent}/target/release
      --prefix=#{prefix}
      --with-default-ssl-backend=openssl
      --disable-debug
      --disable-dependency-tracking
      --disable-silent-rules
      --with-libidn2
      --with-librtmp
      --with-libssh2
      --without-libpsl
      --enable-alt-svc
    ]
#      --with-secure-transport
#      --without-ca-bundle
#      --without-ca-path
#      --with-ca-fallback

    args << if OS.mac?
      "--with-gssapi"
    else
      "--with-gssapi=#{Formula["krb5"].opt_prefix}"
    end

    system "./configure", *args
    system "make"
    system "make", "install"
    system "make", "install", "-C", "scripts"
    libexec.install "scripts/mk-ca-bundle.pl"
  end

  test do
    # Fetch the curl tarball and see that the checksum matches.
    # This requires a network connection, but so does Homebrew in general.
    filename = (testpath/"test.tar.gz")
    system "#{bin}/curl", "-L", stable.url, "-o", filename
    filename.verify_checksum stable.checksum

    system libexec/"mk-ca-bundle.pl", "test.pem"
    assert_predicate testpath/"test.pem", :exist?
    assert_predicate testpath/"certdata.txt", :exist?
  end
end
