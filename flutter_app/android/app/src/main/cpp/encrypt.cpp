#include <seal/seal.h>
#include <sstream>
#include <vector>
#include <string>
#include <cstdlib>
#include <cstring>

using namespace seal;

static std::string to_hex(const std::string &in) {
    static const char *lut = "0123456789ABCDEF";
    std::string out;
    out.reserve(2 * in.size());
    for (unsigned char c : in) {
        out.push_back(lut[c >> 4]);
        out.push_back(lut[c & 15]);
    }
    return out;
}

static std::string from_hex(const char *in) {
    std::string out;
    size_t len = std::strlen(in);
    out.reserve(len / 2);
    for (size_t i = 0; i + 1 < len; i += 2) {
        char high = in[i];
        char low = in[i + 1];
        auto hex_to_val = [](char c) -> unsigned char {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            return 0;
        };
        unsigned char val = (hex_to_val(high) << 4) | hex_to_val(low);
        out.push_back(static_cast<char>(val));
    }
    return out;
}

extern "C" char *encrypt_location(const char *parms_hex,
                                  const char *pk_hex,
                                  double lat,
                                  double lon) {
    EncryptionParameters parms;
    std::string parms_bytes = from_hex(parms_hex);
    std::stringstream parms_ss;
    parms_ss.write(parms_bytes.data(), parms_bytes.size());
    parms.load(parms_ss);

    SEALContext context(parms);
    PublicKey pk;
    std::string pk_bytes = from_hex(pk_hex);
    std::stringstream pk_ss;
    pk_ss.write(pk_bytes.data(), pk_bytes.size());
    pk.load(context, pk_ss);

    BatchEncoder encoder(context);
    Encryptor encryptor(context, pk);

    std::vector<int64_t> vals = {(int64_t)(lat * 1e6), (int64_t)(lon * 1e6)};
    Plaintext plain;
    encoder.encode(vals, plain);
    Ciphertext ct;
    encryptor.encrypt(plain, ct);

    std::stringstream ct_ss;
    ct.save(ct_ss);
    std::string json = "{\"ct\":\"" + to_hex(ct_ss.str()) + "\"}";
    char *out = (char*)malloc(json.size() + 1);
    std::memcpy(out, json.c_str(), json.size() + 1);
    return out;
}

extern "C" void free_string(char *ptr) { std::free(ptr); }
