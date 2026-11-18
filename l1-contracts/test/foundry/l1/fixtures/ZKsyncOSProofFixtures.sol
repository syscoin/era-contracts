// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SYSCOIN: Preserve independently replayed proofs to detect incompatible production key rotations.

/// @notice Genuine v32 Airbender V2 proofs retained for production verifier regression tests.
library ZKsyncOSProofFixtures {
    uint256 internal constant PLONK_V8_SELECTOR = 0x802;
    uint256 internal constant ROUTER_HEADER_WORDS = 2;
    uint256 internal constant STATE_POLY_OPENING_INDEX = 22;

    struct Fixture {
        bytes32 verificationKeyHash;
        uint256[] batchHashes;
        uint256[] publicInputs;
        uint256[] proof;
    }

    // Prover: syscoin/zksync-airbender-prover@ec790318f00e225cd11283a4d5fb7a521f4670a6
    // Calldata SHA-256: 1e9a032e7fdf67267c3db2dcd8f9d8f6d0f0d35eaa10dc478019b6454d318f0e
    function retainedSignedTransfer() internal pure returns (Fixture memory fixture) {
        fixture.verificationKeyHash = 0x9bb49673b5437ada0c0941bb7f35422456a5c7833dd8292bf17f29fe1e9baa97;
        fixture.batchHashes = new uint256[](2);
        fixture.batchHashes[0] = 0x367ac63ff5ef3e2e4a49ffaebb8b88cdd28e82e6db208d202d63d24144775ad4;
        fixture.batchHashes[1] = 0x7dd2a4a1e763bdf6aa46184a9421cbe67975079e5e2969fd85e44c7caea78e30;
        fixture.publicInputs = new uint256[](1);
        fixture.publicInputs[0] = 0x000000006f6b4625f357eb88b0cbfd747ea30ad685a5f115a1bb82900ce5631c;
        fixture.proof = new uint256[](44);
        fixture.proof[0] = 0x291d8ab33d5baea26138a49144ccff5ab749bf10ae4bf87453be90f0cc917f05;
        fixture.proof[1] = 0x0f0be70e0bfce0727add3ce528b5d42446db7c8411f9d8667d076190aa2f095e;
        fixture.proof[2] = 0x205e2baf2951e0bea5dde00ab16c697f95a861ceefdfd088db39797c4e78645e;
        fixture.proof[3] = 0x01967b5404b1816b960b8d534618ca7fa1adee820e7a754982288d997c554ea5;
        fixture.proof[4] = 0x01b6e51057ca7e5dff2c13555a5d588c0045daa98d60a42c584cb1ec0c093770;
        fixture.proof[5] = 0x2e70af3e88e66674c0d2f31a7a93ce84a153127750e376fae6f00e8062887455;
        fixture.proof[6] = 0x2407c961bf0fc0916106600fdfba3fedee02d2df44b92485d19b8088ac84d7d3;
        fixture.proof[7] = 0x0b900290c6c4a273ca7378d2fb8358d1de8792d0d0c77121953271b089887f3b;
        fixture.proof[8] = 0x13d2ec4ce2a4abeab0191fdd061424d90f918b4d32e9ee64997f9505c73ad3a3;
        fixture.proof[9] = 0x2f0473ed4cd9e4d726a1a88832765ea9f98e78bb41f605e943bbbb675c59ef23;
        fixture.proof[10] = 0x06434556bb1131a7ccd496a4ba62893d95d7608dc6b9765207249b49c5052db3;
        fixture.proof[11] = 0x1c21a8e27d0eea54d2294cc4986a72ee99b7b0533155fb5cd2be42d9e4c72b6f;
        fixture.proof[12] = 0x172507d380f338c2ecc53ede857c0a01048c3dd40c7c3d4655bac7e7ddd8d7f6;
        fixture.proof[13] = 0x0f7b0bb54ad2a63fd2f520c503c1459519fb9f20fa350e574ee4205fffcc7637;
        fixture.proof[14] = 0x00e916c475ac90835a6a9cdc722991c5f913f285ee86f5c6b58439ba06b43939;
        fixture.proof[15] = 0x302948210d90fe9868aade3a1e51d08b6a882385ac01b162f7fb14c60bfedb8e;
        fixture.proof[16] = 0x03287f2d1f9934c6c577aee9822d6d4ff38487c56ab6484d8ae6f3db692ec7ca;
        fixture.proof[17] = 0x1262cf6644b90b03cb413c21655b473071c4daf48cfca6832cf429362889aba9;
        fixture.proof[18] = 0x2ed1b6c5907c2d9700b3c991c2d30519f3eb03af088135dfc97e6f495d755761;
        fixture.proof[19] = 0x0c4040328f8384f1ce56ee21978db8405701adc6bb6aacd54b525906510f3326;
        fixture.proof[20] = 0x09f90c64db00c2ba78764bc477f3b44bc99c33af6f03b69bc6f63fe2c03689fb;
        fixture.proof[21] = 0x165ef4be2a3fcff27f78a76a0c92e724d0abf62497e7414bdb4a34f760dcc5e1;
        fixture.proof[22] = 0x098e2a9ae17544944fc57ddf0522362a54d9823546403d78f082d408d36d3152;
        fixture.proof[23] = 0x1caf30accc8eab30c02e6e88eba913b8014a6c827c40799a7b4c32e737db553d;
        fixture.proof[24] = 0x0f2550c20fc717bea001f85da0fbbcf0a341ac967e5c71d5fde48da2b75e0ba1;
        fixture.proof[25] = 0x27af4da53ec1c88b112ede2c35391890a7d8290d964939eb0e5f0c6e7d6958ab;
        fixture.proof[26] = 0x22fb64b49d0b7cc3ed43ec11ad806cb35c1e1cea34c56f3be5e143db39ddd4ae;
        fixture.proof[27] = 0x083b1a960f67c8b51ff6ca3eb08503d9723112e0c33f68f694430bacc2e9bc6f;
        fixture.proof[28] = 0x1598007b5578a46ab4d6340f675933c8a1d7dfacfd421854bf50927e9d454604;
        fixture.proof[29] = 0x099eb01b55991b6aff7d93d5ae697c1e046468ec3890c25222724f68542b8746;
        fixture.proof[30] = 0x1af3dd98a8f411b44a51c385aa0d418204450176ede19d2dfe418e4b6fc5df61;
        fixture.proof[31] = 0x1509e558be2740b175ec2e08adb283ec6f13d9eeca4a62f9cbd7d4c2fbe5c539;
        fixture.proof[32] = 0x153657c4ff51fa68ead932c5a4fb100376dddd732ff7c3306aec808d1183d739;
        fixture.proof[33] = 0x01d2062a1d180c36487faedce8aa919e26d8bb5e1036ed2dfc0a51632f045042;
        fixture.proof[34] = 0x21c360c3c5f6a708982e33c4c7b6293b442bab4e95965a8fc05b34b6c6436f13;
        fixture.proof[35] = 0x037ed88051938c3c953b94234dd04155d86fe6817a8ddafa6943e8371fa5ba6c;
        fixture.proof[36] = 0x1f7bf4175b31312608c6d325cbbf5f3d5e11fe293733900c54b41d230d498fb8;
        fixture.proof[37] = 0x0f3e28d6c08f9995c78bd930f242881b350e2e9d17cfddbef8c2148e55f39fdf;
        fixture.proof[38] = 0x0546f0daaa6f834742d0a5539b1d097ac5e299248f4ef40ba9276b8acafcd145;
        fixture.proof[39] = 0x200f977df6b700f5496ad04b8a40195f734405320d801e921b0cecb02e133de3;
        fixture.proof[40] = 0x2ec350b66d33ff0b24349b7b2ef7e9e4f347e956a37428d349c855a1499feca0;
        fixture.proof[41] = 0x2441cdadb20b833c5239ecebc7c84400a9168aaedb16c288c81a638d97a92bc3;
        fixture.proof[42] = 0x125e4296b00d7104d86ffa0e7d67489aa44d08f4116ed818ce7ec7ca484a8514;
        fixture.proof[43] = 0x130b24bf29061727c1826465b43932ab4931c6f917b1684080f09f3eea8e3be6;
    }

    // Prover: syscoin/zksync-airbender-prover@2a700666cf1d9e66ae6b8a48826261685df1f1e3
    // Calldata SHA-256: 313dafb2858bad12315564455b0919fadb99e23365e42fbd25150d1a28bc61bb
    function correctedSignedTransfer() internal pure returns (Fixture memory fixture) {
        fixture.verificationKeyHash = 0x8e6285da659dac3cfff56dbae3bf445e1524b9f08a9270f19d3361a97f8ce990;
        fixture.batchHashes = new uint256[](2);
        fixture.batchHashes[0] = 0x367ac63ff5ef3e2e4a49ffaebb8b88cdd28e82e6db208d202d63d24144775ad4;
        fixture.batchHashes[1] = 0x7dd2a4a1e763bdf6aa46184a9421cbe67975079e5e2969fd85e44c7caea78e30;
        fixture.publicInputs = new uint256[](1);
        fixture.publicInputs[0] = 0x000000006f6b4625f357eb88b0cbfd747ea30ad685a5f115a1bb82900ce5631c;
        fixture.proof = new uint256[](44);
        fixture.proof[0] = 0x0aa7f11cae66136b5483c439f3a9e64c2847de62134c53b046cb051daf052123;
        fixture.proof[1] = 0x2018bcb717f3a8feddec7f25df4bef7a70d6a8f62340610154b7416420c8068f;
        fixture.proof[2] = 0x0e26c9b8cafa801677513a9bdfc2d23aee19a7a1e80492a859f90be899601e7c;
        fixture.proof[3] = 0x1e37487823caa156a505a9b8aedf9125eba639e0ea6680b47329b2aef2a605d3;
        fixture.proof[4] = 0x1cc7aec443326c118d48012785d4289b9f939a92d1b4ebf74d5ae7645ed70c00;
        fixture.proof[5] = 0x1e80a76276bc6d60f4200971fb0b51f40d906432b1fa47d97f972a5f0a34a1e3;
        fixture.proof[6] = 0x2472bc42870dd753a879884bfa2373090616bec687d0feb99762b471f59643fa;
        fixture.proof[7] = 0x2dcb6b5b7340fe614a49e6a33c8120ec7a2612e17fefe62ac4aca4460afac069;
        fixture.proof[8] = 0x1718d716e101065708a071d7830d540491deb163178439c0917a3a05cfad94a7;
        fixture.proof[9] = 0x243f44bde835d97ffe8e91abfad2a3a8a1a9b228ccaeeab179e66b04d4a9bce6;
        fixture.proof[10] = 0x2322cb436906e6135cd7ceb2da554b2638f99fc8a7252b2b03772fdda513c84d;
        fixture.proof[11] = 0x20b8b706912e45f5f064ff062b6089fc2d721e853e79afd8955539ba0ab14dee;
        fixture.proof[12] = 0x0e1026c6f2903c9f3708a267efd8a3d2b5d0c0c2fcc1559c4b8f0dd80b3bcbc4;
        fixture.proof[13] = 0x216163d7d7725bb17062c9bdb5637dc12e899c71f968c5bc4c0601850812fff7;
        fixture.proof[14] = 0x2cc72010d93972e28345b87b44cb7ff5936d08d9aab8b7b8dd6cdad1c0c70f3a;
        fixture.proof[15] = 0x1f8262802f8d06a1fddb1db204b91d5a0d38b5f7678dc2d2b5ec37ff459664b0;
        fixture.proof[16] = 0x073b688b84bb170219288bee0e0827f15c3e36b729a92943265fd3f36d511129;
        fixture.proof[17] = 0x01cf8708f28cb682d9db7546dc0a1231604ab486949999e1b1e99cdc0979f3d5;
        fixture.proof[18] = 0x1230a935649b8a4c522aa2ad03ffbd534b174ab3d12e433781f0547490422e4b;
        fixture.proof[19] = 0x2095da29fd5b77e8f05004833780a23b681509b19481f666f5ac6c60b918873d;
        fixture.proof[20] = 0x0079eca024d66d771305d5c49f584f582d3aafc3664e797ad89a94d970b37229;
        fixture.proof[21] = 0x2b7563755a4c2182088637cf3147e72f96a0cfd2af44ef4d9f97409d1ff0a73a;
        fixture.proof[22] = 0x2fee4e3f47a641675e6f60ca2ed878fe4d40c2a6645484c5f02bbdc5d23d9024;
        fixture.proof[23] = 0x2c9fdff7d2b81e2ef594040972f5aa36c5e9b6427cbb44657f27e74df74b357c;
        fixture.proof[24] = 0x0b57801d4a55885debc692d33e58fda1c041a843da8167c6c4ab6c2f6bbf2f54;
        fixture.proof[25] = 0x2c2eedfaf9806f034b76f256f6e9445b4bb9dd795751167be9c4a8d59d44c7b6;
        fixture.proof[26] = 0x1b21962d7960fa8b560b5facf12a807210ebce83e3838bc7ae997c6e2204e160;
        fixture.proof[27] = 0x27adad609883ce7c795b01777b41383e10ab5c2313bc780783373492650c96e6;
        fixture.proof[28] = 0x049b15c7fa412c4f19874544d409eb158713b18f3ca4a3b80580b5a854ed1c7c;
        fixture.proof[29] = 0x1b10ad45d35680ae68e7f607d8cc843873fcd4c6c576add05420851dd27419de;
        fixture.proof[30] = 0x05e1deab400f44352d01083b4df6e41c3d24ad3346337800d6cf87671924e3de;
        fixture.proof[31] = 0x035da20ae0c14638504aa0c4b2cf9aa417eae7639a4497bcc51b2e4eec3a13c7;
        fixture.proof[32] = 0x0309df9c77138f293e3e281fa2393124adda6765233860c46ae0205e8c6d83a9;
        fixture.proof[33] = 0x0955d9b16409203c655306f2a51793434f0c2268a0019e1734aed54a41fe43fb;
        fixture.proof[34] = 0x2cb173ca22a773050a5f2c8bee19d0f16dc252e7e8adb80dd80821cc6edbaf06;
        fixture.proof[35] = 0x301482b5562be0ae62b4565fff9a0a59517c2dfc2e742749535671e44c98054e;
        fixture.proof[36] = 0x26f37674ffec0e5baaf47bec3f788e07607999ae60688b2e7be511cfebf4e98f;
        fixture.proof[37] = 0x285f174badcc87e6c234b245562bab84efb6595f9fd591917ae1b74964cdb5ab;
        fixture.proof[38] = 0x06fb013bdf8135c834c277d94b31c0509752f41e3e448bb5cd41bea77a9fca97;
        fixture.proof[39] = 0x001393974e698e8d57921b4a31ad6e4905d700005265af143c9649b59de49d0c;
        fixture.proof[40] = 0x1ae243bb2f3ef01ab1127da06a8a4a47507c4b47d12936d214c378f0204134fb;
        fixture.proof[41] = 0x1c85f9643b873d8b83868842b429751ee460d6bd40613d4abb55c1f0e8ee345d;
        fixture.proof[42] = 0x07e24c338343c69e394aafb3dd08adacdec5958b6a57dfe844e9b7958a9fb446;
        fixture.proof[43] = 0x3046878e55b73d49d5dd0b2bdeae313c61e118b262ca97a523f16720bb2b5d50;
    }

    // Prover: syscoin/zksync-airbender-prover@2a700666cf1d9e66ae6b8a48826261685df1f1e3
    // Calldata SHA-256: 17ffe67e40b4012d6b3eee2e381bd4af1d6e7c7b0fe024f5c9c384d89a536037
    function correctedMinimal() internal pure returns (Fixture memory fixture) {
        fixture.verificationKeyHash = 0x8e6285da659dac3cfff56dbae3bf445e1524b9f08a9270f19d3361a97f8ce990;
        fixture.batchHashes = new uint256[](2);
        fixture.batchHashes[0] = 0xf24738326ca32c8347c6881f4a7507b45cd47e03abe907a1f121f5484c98a6fe;
        fixture.batchHashes[1] = 0xff1d448a4db7c0641de24cc41d790699500226a46210d85f82b4b5d8099fc076;
        fixture.publicInputs = new uint256[](1);
        fixture.publicInputs[0] = 0x00000000d9eb74878ed99039b9044192eea668898992c489030032afcf1b9337;
        fixture.proof = new uint256[](44);
        fixture.proof[0] = 0x0deb3f69b63f7c9d352071b335c3ac42319ea91541ea887b4b1350bff1563914;
        fixture.proof[1] = 0x090f640a8a52e8788a76156cf1444f17ca88dd2f68f08609a60f1d560952545f;
        fixture.proof[2] = 0x218db00575a15d60cd102e3b5d4893ce60711877686a0b34504bff480c5c31e2;
        fixture.proof[3] = 0x1261a0d58716438efb3d1d9bb7a79a83613adf260b48c3da50aca4b971ce3c22;
        fixture.proof[4] = 0x2cc41006315e4ef5774c1f8c849992a329311ede54f7cc621370ddee9e960189;
        fixture.proof[5] = 0x18b92a1915e133dbef081e3fd6eff21a5c064302b18184fab99317a61ae8375c;
        fixture.proof[6] = 0x0759a11ae62fd7e89fad71e47a6b18c00aad1a45b1eacb41bbf3f59897943c99;
        fixture.proof[7] = 0x28ab05b4812b0d359953f136b1034da9db53677b9feb46b61d6222839a867c75;
        fixture.proof[8] = 0x2200ecc402fec8b0cdad90bccc43ecd5d211dfee66c78e31b508a68fd1421540;
        fixture.proof[9] = 0x0d4f41cafdb496923d8f1c1008833ca407211926372ddce8424e0721f3a42dc5;
        fixture.proof[10] = 0x15508af162128ea9a4a4b01bfb2b54b66769038e69bfb7e8e71abe212a80e569;
        fixture.proof[11] = 0x02198d5dbb445b48b41538a8099905ead6b5e4991085e894ed0105ea8973dcae;
        fixture.proof[12] = 0x1ae6c86278df061e780927ab549b1bfbee94679f6560d40d45b798fd19ab2b5e;
        fixture.proof[13] = 0x1c4f39e282a729fbb6cad1951e6cd6135df96a2b0a5b75fe2a423cfbcf23377a;
        fixture.proof[14] = 0x028028b43f493884a2e3bf43664a89d6e9915392cdabcf0135ef35e5dff913a5;
        fixture.proof[15] = 0x244e6e875a0a532187c0c4e7f6b393622676cc19bb77a0c097b6dbf5c7267c23;
        fixture.proof[16] = 0x1b85f3c42068c25f59745992f9dd8d07c2f9e47083d4f58fbf38b73004a83d89;
        fixture.proof[17] = 0x174b1cb2515558e6924b00cc5c1954c7e964122e582d56d70b62de381e5fcd31;
        fixture.proof[18] = 0x0cabe2ba1e4fa3f3b9435b7d285c04fab32bbc440e780afcafe0e4320e4121b8;
        fixture.proof[19] = 0x089401b9c1f8b262339307512e2ca578898c9420eb5378412b83a8a2f7ca06f1;
        fixture.proof[20] = 0x2b019f05e81363e5157337fa8f8ff201e06eafdbdb2c9a3a8ae4497a9ddf3276;
        fixture.proof[21] = 0x26c21bb4e355414eb7f1a0cba09ac1ec5ed9d7fb9349bbae032e8523a1a81a19;
        fixture.proof[22] = 0x0bc6eec6f79d021858f0a7de33afb670e0a0fdeb18a728f45d00bb757c17d06d;
        fixture.proof[23] = 0x0d5996e35a4be2a2907a3f29d8f363b9ab78d319d1c98d6b30808d06deb44f8f;
        fixture.proof[24] = 0x10e0d2d109431e3448a33419021bb120d9818270fae27cf14661c7fe9256eca5;
        fixture.proof[25] = 0x2b2339548f18c63f25eea8f60f4490dfbdb248d61a8d431affd24c41fa18951d;
        fixture.proof[26] = 0x2dc2f870a67c56f3d615a8c412984c25c8e8615b29c634a8a1338b468f5a0d8e;
        fixture.proof[27] = 0x154d891a663c0260240476dfc43a4a70806ffafefe1b759a4fc8d23c80b8b2f4;
        fixture.proof[28] = 0x1e3dde5def9113322874717498964244b111951bb51f4df7517a3c4e32e1ce1e;
        fixture.proof[29] = 0x151b608afadd202841bf7fbedfa0bbba480d6840872227b4b483bb3ff6d1ca57;
        fixture.proof[30] = 0x2b96b7249486e8ece889c37fa19bfed64c2f65c9ae8dadb6a433b1eee51d89b3;
        fixture.proof[31] = 0x18b44e8951bb3d19614174af9a6bddd9a447129e435a3b313cf893c976c823f3;
        fixture.proof[32] = 0x12c910c3c9e5fe36531b211130cc3047f40fbc5cb532526d9a62719cee9d34e8;
        fixture.proof[33] = 0x04db626c905157ba644b478b507f11377178af2b2a5952289b6057349fd3da37;
        fixture.proof[34] = 0x06868e50652349dbf065f487a2195ffe4dc95991983197765a7bf41f940df9bc;
        fixture.proof[35] = 0x049eca9f7e1a5ff6836daf6cf0bdbd661e032275b1af90fd621f5befbca6f11d;
        fixture.proof[36] = 0x2416f70a8458fef28eb73135619833dbcd3ae01b9f68a83307de6418acdace2f;
        fixture.proof[37] = 0x0c8790791f08331fc989e2b18f4580a0ae4cd6f22770dd75360be204af235457;
        fixture.proof[38] = 0x2528a4e4eec333c44ab99982f6694f414e2d35e97c41d8ef1ad01d97978101ea;
        fixture.proof[39] = 0x1adddf25f838d9e53c372c49c75a0573ea75a3289ffe6631d032b767c27333a9;
        fixture.proof[40] = 0x02212113ef18b11bdafb4247b7716901b6b7f531588fcf66ff034780517cb989;
        fixture.proof[41] = 0x1e012aad61526fc40472aee004d023c5104b382071f88820e685c1e3d922bbd7;
        fixture.proof[42] = 0x2679e0024056a0f98cd33bd9c5c31daab38cedbab7308bc487ee09e3ecd815f6;
        fixture.proof[43] = 0x2e21cbfcea58180e8d4cf8c23f8e5629ac468794ffa5ec98d46befbbece55301;
    }
}
