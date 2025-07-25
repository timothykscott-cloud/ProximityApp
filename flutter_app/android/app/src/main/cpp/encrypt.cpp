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

extern "C" char *encrypt_location(double lat, double lon) {
    EncryptionParameters parms(scheme_type::bfv);
    parms.set_poly_modulus_degree(4096);
    parms.set_coeff_modulus(CoeffModulus::BFVDefault(4096));
    parms.set_plain_modulus(PlainModulus::Batching(4096, 20));

    SEALContext context(parms);
    KeyGenerator keygen(context);
    SecretKey sk = keygen.secret_key();
    PublicKey pk;
    keygen.create_public_key(pk);

    BatchEncoder encoder(context);
    Encryptor encryptor(context, pk);

    std::vector<int64_t> vals = {(int64_t)(lat * 1e6), (int64_t)(lon * 1e6)};
    Plaintext plain;
    encoder.encode(vals, plain);
    Ciphertext ct;
    encryptor.encrypt(plain, ct);

    std::stringstream ct_ss; ct.save(ct_ss);
    std::stringstream sk_ss; sk.save(sk_ss);
    std::stringstream pa_ss; parms.save(pa_ss);

    std::string json = "{\"ct\":\"" + to_hex(ct_ss.str()) + "\",\"sk\":\"" + to_hex(sk_ss.str()) + "\",\"parms\":\"" + to_hex(pa_ss.str()) + "\"}";
    char *out = (char*)malloc(json.size() + 1);
    std::memcpy(out, json.c_str(), json.size() + 1);
    return out;
}

extern "C" void free_string(char *ptr) { std::free(ptr); }
