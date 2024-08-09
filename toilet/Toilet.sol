// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.0 <0.9.0;

import "../hts-precompile/HederaResponseCodes.sol";
import "../hts-precompile/IHederaTokenService.sol";
import "../hts-precompile/HederaTokenService.sol";
import "../hts-precompile/ExpiryHelper.sol";
import "../hts-precompile/KeyHelper.sol";

contract Toilet is ExpiryHelper, KeyHelper, HederaTokenService {

    struct Ticket {
        int64 serial;
        bool available;
    }

    mapping(string => address) public toiletAddress;
    mapping(address => address) public toiletOwner;
    mapping(address => Ticket[]) public toiletTicket;

    constructor() {}

    function registerToilet(string memory name, string memory symbol, string memory memo, int64 maxSupply, string memory uri)
        external payable returns (address){

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        keys[0] = getSingleKey(KeyType.SUPPLY, KeyValueType.CONTRACT_ID, address(this));
        IHederaTokenService.HederaToken memory token;
        token.name = name;
        token.symbol = symbol;
        token.memo = memo;
        token.treasury = address(this);
        token.tokenSupplyType = true;
        token.maxSupply = maxSupply;
        token.tokenKeys = keys;
        token.freezeDefault = false;
        token.expiry = createAutoRenewExpiry(address(this), 7_776_000); // Contract auto-renews the token 90days

        (int responseCode, address createdToken) = HederaTokenService.createNonFungibleToken(token);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("failed to create non-fungible token");
        }
        int64[] memory serial;
        for (int64 i = 0; i < maxSupply; i++ ) {
            bytes memory metadata = bytes(uri);
            bytes[] memory metadatas = new bytes[](1);
            metadatas[0] = metadata;
            (responseCode, ,serial) = HederaTokenService.mintToken(createdToken, 0, metadatas);
            if(responseCode != HederaResponseCodes.SUCCESS){
                revert("failed to mint non-fungible token");
            }
            toiletTicket[msg.sender].push(Ticket(serial[0], true));
        }
        
        toiletAddress[name] = createdToken;
        toiletOwner[createdToken] = msg.sender;

        return createdToken;
    }

    function enterToilet(string memory name) public returns (uint256) {
        address token = toiletAddress[name];
        address owner = toiletOwner[token];
        uint256 ticket;
        for (ticket = 0; ticket < toiletTicket[owner].length; ticket++) {
            if (toiletTicket[owner][ticket].available) {
                break;
            }
        }
        if (ticket == toiletTicket[owner].length) {
            revert("not available toilet");
        }
        int responseCode = HederaTokenService.transferNFT(token, owner, msg.sender, toiletTicket[owner][ticket].serial);
        if (responseCode == HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT) {
            responseCode = HederaTokenService.associateToken(msg.sender, token);
            if (responseCode != HederaResponseCodes.SUCCESS) {
                revert("failed to associate non-fungible token");
            }
            responseCode = HederaTokenService.transferNFT(token, owner, msg.sender, toiletTicket[owner][ticket].serial);
            if (responseCode != HederaResponseCodes.SUCCESS) {
                revert("failed to transfer non-fungible token");
            }
        } else if (responseCode != HederaResponseCodes.SUCCESS) {
                revert("failed to transfer non-fungible token");
        }
        toiletTicket[owner][ticket].available = false;
        return ticket;
    }

    function exitToilet(string memory name, uint256 ticket) public {
        address token = toiletAddress[name];
        address owner = toiletOwner[token];
        int responseCode = HederaTokenService.transferNFT(token, msg.sender, owner, toiletTicket[owner][ticket].serial);
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("failed to transfer non-fungible token");
        }
        toiletTicket[owner][ticket].available = true;
    }
}