// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract MockVotingEscrow {
    mapping(uint256 => address) internal owners;
    mapping(uint256 => address) public claimRedirect;
    mapping(address => mapping(uint256 => uint256)) public pastVotes;
    mapping(address => uint8[]) internal configActions;
    mapping(address => string) public configDescription;
    mapping(address => bool) public configActive;

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = owners[tokenId];
        require(owner != address(0), "ERC721NonexistentToken");
    }

    function mint(uint256 tokenId, address owner) external {
        owners[tokenId] = owner;
    }

    function setPastVotes(address account, uint256 timepoint, uint256 votes) external {
        pastVotes[account][timepoint] = votes;
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        return pastVotes[account][timepoint];
    }

    function setConduitApprovalConfig(uint8[] calldata actions, string calldata description) external {
        require(!configActive[msg.sender], "Conduit already configured");
        require(actions.length > 0, "Empty actions array");
        configActions[msg.sender] = actions;
        configDescription[msg.sender] = description;
        configActive[msg.sender] = true;
    }

    function squat(address conduit) external {
        configActive[conduit] = true;
    }

    function getConduitActions(address conduit) external view returns (uint8[] memory) {
        return configActions[conduit];
    }

    function setConduitApproval(address conduit, uint256 tokenId, bool approve) external {
        require(configActive[conduit], "Invalid conduit type");
        require(owners[tokenId] == msg.sender, "Not token owner");
        claimRedirect[tokenId] = approve ? conduit : address(0);
    }

    function isApprovedClaimRedirectOrOwner(address operator, uint256 tokenId) external view returns (bool) {
        return owners[tokenId] == operator || claimRedirect[tokenId] == operator;
    }
}
