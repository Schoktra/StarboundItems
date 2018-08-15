import React from 'react'
import { shallow } from 'enzyme'
import InfoBar from './InfoBar'

function setup(props) {
  return shallow(<InfoBar {...props} />)
}

describe('InfoBar', () => {
  let wrapper = setup()

  it('renders with four panels', () => {
    expect(wrapper.find('Panel').length).toBe(4)
  })
})
