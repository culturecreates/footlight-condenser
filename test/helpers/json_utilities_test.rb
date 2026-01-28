require 'test_helper'

class JsonUtilitiesTest < ActiveSupport::TestCase
  test 'returns true for equal hashes' do
    h1 = { a: 1, b: 2 }
    h2 = { a: 1, b: 2 }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'returns false for unequal hashes' do
    h1 = { a: 1 }
    h2 = { a: 2 }
    refute JsonUtilities.compare_json(h1, h2)
  end

  test 'returns true for equal arrays' do
    arr1 = [1, 2, 3]
    arr2 = [1, 2, 3]
    assert JsonUtilities.compare_json(arr1, arr2)
  end

  test 'returns false for arrays with different elements' do
    arr1 = [1, 2, 3]
    arr2 = [3, 2, 1]
    refute JsonUtilities.compare_json(arr1, arr2)
  end

  test 'ignores created_at and updated_at keys in hashes' do
    h1 = { a: 1, created_at: '2020-01-01' }
    h2 = { a: 1, created_at: '2021-01-01' }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'ignores both created_at and updated_at' do
    h1 = { a: 1, b: 2, created_at: 'y', updated_at: 'y' }
    h2 = { a: 1, b: 2, created_at: 'z', updated_at: 'z' }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'handles deeply nested structures' do
    h1 = { a: [{ b: 2, updated_at: "yesterday" }], c: 3 }
    h2 = { a: [{ b: 2, updated_at: "today" }], c: 3 }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'returns false for different nested structures' do
    h1 = { a: [{ b: 2 }], c: 3 }
    h2 = { a: [{ b: 3 }], c: 3 }
    refute JsonUtilities.compare_json(h1, h2)
  end

  test 'returns false for mismatched types' do
    assert_equal false, JsonUtilities.compare_json([1,2], { a: 1, b: 2 })
  end

  test 'hashes are equal when keys are symbols or strings' do
    h1 = { 'a' => 1, 'b' => 2 }
    h2 = { a: 1, b: 2 }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'deep nested symbol/string keys are treated as equal' do
    h1 = { data: [{ user: { id: 1 } }] }
    h2 = { 'data' => [{ 'user' => { 'id' => 1 } }] }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'empty arrays are equal' do
    assert JsonUtilities.compare_json([], [])
  end

  test 'empty hashes are equal' do
    assert JsonUtilities.compare_json({}, {})
  end

  test 'hashes are equal regardless of key order' do
    h1 = { a: 1, b: 2 }
    h2 = { b: 2, a: 1 }
    assert JsonUtilities.compare_json(h1, h2)
  end

  test 'arrays are not equal if order differs' do
    arr1 = [{a: 1}, {b: 2}]
    arr2 = [{b: 2}, {a: 1}]
    refute JsonUtilities.compare_json(arr1, arr2)
  end

  test 'handles JSON string input' do
    json1 = '{"a":1,"b":2}'
    json2 = { a: 1, b: 2 }
    assert JsonUtilities.compare_json(json1, json2)
  end

  test 'returns false for unequal JSON string inputs' do
    json1 = '{"a":1,"b":2}'
    json2 = '{"a":2,"b":2}'
    refute JsonUtilities.compare_json(json1, json2)
  end
  
  test 'returns false if objects are not hash or array' do
    assert_equal false, JsonUtilities.compare_json(123, [1, 2, 3])
    assert_equal false, JsonUtilities.compare_json({ a: 1 }, nil)
    assert_equal false, JsonUtilities.compare_json('jsonator', { a: 1 })
  end

end
