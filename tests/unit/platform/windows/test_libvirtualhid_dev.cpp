/**
 * @file tests/unit/platform/windows/test_libvirtualhid_dev.cpp
 * @brief Tests for the experimental libvirtualhid-dev gamepad report mapping.
 */

// test includes
#include "../../../tests_common.h"

#ifdef _WIN32
  // standard includes
  #include <cstdint>

  // local includes
  #include <src/platform/common.h>
  #include <src/platform/windows/input.h>

TEST(LibvirtualhidDevAxisTest, MapsTheSignedRangeOntoTheFullByteRange) {
  EXPECT_EQ(platf::libvirtualhid_dev::scale_axis(-32768), 0);
  EXPECT_EQ(platf::libvirtualhid_dev::scale_axis(32767), 255);
  // The signed zero point lands just below the byte midpoint with integer math.
  EXPECT_EQ(platf::libvirtualhid_dev::scale_axis(0), 127);
}

TEST(LibvirtualhidDevAxisTest, IsMonotonicAndNeverOverflowsTheByteRange) {
  int previous = -1;
  for (std::int32_t value = -32768; value <= 32767; ++value) {
    const int mapped = platf::libvirtualhid_dev::scale_axis(static_cast<std::int16_t>(value));
    EXPECT_GE(mapped, 0);
    EXPECT_LE(mapped, 255);
    EXPECT_GE(mapped, previous) << "axis mapping must not decrease at " << value;
    previous = mapped;
  }
}

TEST(LibvirtualhidDevButtonsTest, MapsEachMoonlightFlagToItsReportBit) {
  struct mapping_t {
    std::uint32_t flag;
    std::uint16_t bit;
  };

  constexpr mapping_t mappings[] = {
    {platf::A, 1u << 0},
    {platf::B, 1u << 1},
    {platf::X, 1u << 2},
    {platf::Y, 1u << 3},
    {platf::LEFT_BUTTON, 1u << 4},
    {platf::RIGHT_BUTTON, 1u << 5},
    {platf::LEFT_STICK, 1u << 6},
    {platf::RIGHT_STICK, 1u << 7},
    {platf::BACK, 1u << 8},
    {platf::START, 1u << 9},
    {platf::HOME, 1u << 10},
    {platf::MISC_BUTTON, 1u << 11},
    {platf::DPAD_UP, 1u << 12},
    {platf::DPAD_DOWN, 1u << 13},
    {platf::DPAD_LEFT, 1u << 14},
    {platf::DPAD_RIGHT, 1u << 15},
  };

  std::uint16_t all_bits = 0;
  std::uint32_t all_flags = 0;
  for (const auto &mapping : mappings) {
    EXPECT_EQ(platf::libvirtualhid_dev::encode_buttons(mapping.flag), mapping.bit);
    all_bits |= mapping.bit;
    all_flags |= mapping.flag;
  }

  EXPECT_EQ(platf::libvirtualhid_dev::encode_buttons(all_flags), all_bits);
}

TEST(LibvirtualhidDevButtonsTest, IgnoresNeutralAndUnmappedFlags) {
  EXPECT_EQ(platf::libvirtualhid_dev::encode_buttons(0), 0);
  // Flags the single-gamepad backend does not expose must not set stray bits.
  EXPECT_EQ(platf::libvirtualhid_dev::encode_buttons(platf::PADDLE1 | platf::TOUCHPAD_BUTTON), 0);
}
#endif
